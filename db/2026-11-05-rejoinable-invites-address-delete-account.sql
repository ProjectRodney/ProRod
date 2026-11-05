-- Applied 5 November 2026 to the ProRod project (migration rejoinable_invites_venue_address_delete_account).
-- 1. A valid invitation can be used again by the same account after leaving or expiry; rescanning
--    during a live session still returns that session unchanged (the unique (user_id, invite_id)
--    constraint is dropped and private.join_venue is rewritten accordingly).
-- 2. private.venues gains an address column and the 'barber' category; preview_venue returns the address.
-- 3. public.delete_account() lets a member delete their own account (cascades profile and sessions).
-- The resulting definitions are in accounts-and-venues.sql (snapshot) and verified by verify-accounts-and-venues.sql.
do $$ declare c text; begin
  select conname into c from pg_constraint
  where conrelid = 'public.venue_sessions'::regclass and contype = 'u'
    and array_length(conkey, 1) = 2
    and conkey @> array[(select attnum from pg_attribute where attrelid = 'public.venue_sessions'::regclass and attname = 'user_id'),
                       (select attnum from pg_attribute where attrelid = 'public.venue_sessions'::regclass and attname = 'invite_id')];
  if c is not null then execute format('alter table public.venue_sessions drop constraint %I', c); end if;
end $$;
alter table private.venues drop constraint if exists venues_category_check;
alter table private.venues add constraint venues_category_check
  check (category in ('restaurant','pub','chicha','nightclub','barber','test'));
alter table private.venues add column if not exists address text;
-- preview_venue, join_venue, delete_account: see accounts-and-venues.sql for the current bodies.

-- Same day, migration profile_bio_avatar_required: profiles.bio / avatar_path / avatar_updated_at, private
-- 'avatars' storage bucket with per-member policies, private.profile_complete(), save_profile with bio and
-- photo (photo must be the member's own object), join_venue requires a complete profile.

-- Same day, migration venue_discovery_blocks: public.blocks, private.blocked_between(), private.live_session(),
-- venue_members() (members present in the caller's live venue: name, age, bio, photo path), storage policy
-- avatars_venue_select (photos readable only while co-present and unblocked).

-- Same day, migration introductions_conversations_safety: public.introductions, conversations, messages,
-- conversation_reads, reports (no member grants; all access through definer functions): send_introduction,
-- respond_introduction (consent = accept + reply), my_inbox, conversation_messages, send_message,
-- close_conversation (neutral notice), block_member (closes everything both ways), report_member.
