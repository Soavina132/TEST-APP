-- Profiles : colonnes referral / phone
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS referral_code       text UNIQUE,
  ADD COLUMN IF NOT EXISTS referred_by         uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS referral_unlocked   boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS phone_verified      boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS phone_number        text;

-- Générer un code parrainage pour les profils qui n'en ont pas
UPDATE public.profiles
SET referral_code = upper(substring(md5(id::text || random()::text) from 1 for 8))
WHERE referral_code IS NULL;

-- Transactions : colonnes attendues par les migrations suivantes
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='transactions') THEN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='transactions' AND column_name='type') THEN
      IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='transactions' AND column_name='kind') THEN
        EXECUTE 'ALTER TABLE public.transactions ADD COLUMN type text';
        EXECUTE 'UPDATE public.transactions SET type = kind WHERE type IS NULL';
      ELSE
        EXECUTE 'ALTER TABLE public.transactions ADD COLUMN type text';
      END IF;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='transactions' AND column_name='ref_id') THEN
      EXECUTE 'ALTER TABLE public.transactions ADD COLUMN ref_id uuid';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='transactions' AND column_name='note') THEN
      EXECUTE 'ALTER TABLE public.transactions ADD COLUMN note text';
    END IF;
  END IF;
END; $$;