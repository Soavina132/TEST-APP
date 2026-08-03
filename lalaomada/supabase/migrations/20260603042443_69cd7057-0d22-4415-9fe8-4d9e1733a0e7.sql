-- Remove broad SELECT policies that allow listing all files in public buckets.
-- Public file access via public URLs continues to work (CDN), but the storage API
-- list/select operations are no longer exposed to clients.
DROP POLICY IF EXISTS "Avatars are publicly readable" ON storage.objects;
DROP POLICY IF EXISTS "avatars_public_read" ON storage.objects;