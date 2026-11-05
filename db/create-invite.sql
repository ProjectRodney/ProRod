-- Issue a venue invitation (the token behind a venue's QR code). ProRod project only.
-- Run in the Supabase SQL editor (postgres role). The token is shown ONCE; only its hash is stored.
-- Change the venue name and validity below, then copy the returned URL into a QR code generator.
--
-- Venue listing:   select id, name, category, duration_minutes, active from private.venues order by name;
-- Revoke a token:  update private.venue_invites set revoked_at = now() where id = '<invite id>';

with params as (
  select
    (select id from private.venues where name = 'PRod · Lieu de test' and active limit 1) as venue_id,
    interval '7 days' as validity,
    'https://rdzoagbe.github.io/prod-app/account.html' as site_url
),
token as (
  select translate(encode(extensions.gen_random_bytes(32), 'base64'), '+/=', '-_') as value
),
inserted as (
  insert into private.venue_invites (venue_id, token_hash, expires_at)
  select params.venue_id, encode(extensions.digest(token.value, 'sha256'), 'hex'), now() + params.validity
  from params, token
  where params.venue_id is not null
  returning id, venue_id, expires_at
)
select inserted.id as invite_id, v.name as venue, inserted.expires_at,
       params.site_url || '?venue=' || token.value as invitation_url
from inserted join private.venues v on v.id = inserted.venue_id, token, params;
