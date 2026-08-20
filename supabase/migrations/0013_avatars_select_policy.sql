-- Avatar uploads use upsert (INSERT ... ON CONFLICT DO UPDATE inside
-- storage-api), and Postgres requires a SELECT policy to read the
-- conflicting row. Without it, re-uploading an avatar fails with
-- "new row violates row-level security policy". The bucket is public,
-- so read access for API roles is not a widening of exposure.
drop policy if exists avatars_public_select on storage.objects;
create policy avatars_public_select on storage.objects
  for select to authenticated, anon
  using (bucket_id = 'avatars');
