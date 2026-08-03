-- Daily login bonus with a 7-day streak cycle.
-- Uses the pre-existing profiles.daily_streak / profiles.last_daily_claim columns,
-- which were defined in the schema but never wired up to any feature.

create or replace function public.claim_daily_bonus()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_last_date date;
  v_streak int;
  v_new_streak int;
  v_bonus numeric;
  v_today date := (now() at time zone 'Indian/Antananarivo')::date;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select last_daily_claim::date, coalesce(daily_streak, 0)
    into v_last_date, v_streak
  from public.profiles
  where id = v_uid
  for update;

  if v_last_date = v_today then
    return json_build_object(
      'success', false,
      'already_claimed', true,
      'streak', v_streak
    );
  end if;

  if v_last_date = v_today - 1 then
    v_new_streak := v_streak + 1;
  else
    v_new_streak := 1;
  end if;

  if v_new_streak > 7 then
    v_new_streak := 1;
  end if;

  v_bonus := 300 + (v_new_streak * 200);
  if v_new_streak = 7 then
    v_bonus := v_bonus + 2000;
  end if;

  update public.profiles
  set balance_ar = balance_ar + v_bonus,
      daily_streak = v_new_streak,
      last_daily_claim = now()
  where id = v_uid;

  return json_build_object(
    'success', true,
    'already_claimed', false,
    'streak', v_new_streak,
    'bonus', v_bonus
  );
end;
$$;

grant execute on function public.claim_daily_bonus() to authenticated;
