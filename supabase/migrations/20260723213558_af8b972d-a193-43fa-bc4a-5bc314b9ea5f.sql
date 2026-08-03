-- Recopie le numéro de téléphone (issu du faux e-mail) dans auth.users.phone
-- puis supprime l'e-mail fictif, pour permettre la connexion par téléphone.
UPDATE auth.users u
SET phone = COALESCE(
      u.phone,
      substring(u.email FROM 'phone(\d+)@phone\.lalaomada\.local')
    ),
    phone_confirmed_at = COALESCE(u.phone_confirmed_at, u.created_at)
WHERE u.email LIKE 'phone%@phone.lalaomada.local';

UPDATE auth.users
SET email = NULL,
    email_confirmed_at = NULL
WHERE email LIKE 'phone%@phone.lalaomada.local';