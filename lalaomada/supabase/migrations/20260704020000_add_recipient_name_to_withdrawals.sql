ALTER TABLE public.withdrawals ADD COLUMN IF NOT EXISTS recipient_name text;
COMMENT ON COLUMN public.withdrawals.recipient_name IS 'Nom complet du destinataire Mobile Money fourni par l utilisateur lors du retrait';
