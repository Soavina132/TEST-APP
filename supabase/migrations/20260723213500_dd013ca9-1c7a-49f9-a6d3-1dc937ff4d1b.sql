ALTER TABLE public.profiles ALTER COLUMN email DROP NOT NULL;
UPDATE public.profiles SET email = NULL WHERE email LIKE 'phone%@phone.lalaomada.local';