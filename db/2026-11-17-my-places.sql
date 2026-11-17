-- UPZONE, 17 November 2026: « Mes lieux » (client request, design validated by the client).
-- Run once in the Supabase SQL editor of the ProRod project, after db/2026-11-17-pro-accounts.sql. Safe to run again.
--
-- The scan screen lists the places the member visited in the last 90 days, so they can find a place again.
-- No new data is collected: the list is read from the member's own visits (public.venue_sessions), which the member
-- can already read and download (my_data_export).
-- • Entering still needs the QR code scanned on site (join_venue is unchanged): the list never lets anyone in.
-- • Private: only the member's own visits, never anyone else's, never shown to the venue.
-- • 90 days; one-off events (category « event ») are not listed.
-- • « Retirer de mes lieux » hides a place, « Effacer l'historique » hides every place: the visits stay on the server
--   for safety (reports and blocks rely on them) but are no longer listed. A later visit shows the place again.
-- • Closed places are listed as closed (no action). The place's current announcement is shown (client decision).

alter table public.venue_sessions add column if not exists history_hidden_at timestamptz;

create or replace function private.my_places() returns jsonb
 language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_person();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'venue', x.venue_id, 'name', v.name, 'category', v.category, 'open', v.active,
      'visits', x.visits, 'last_visit', x.last_visit,
      'announcement', case when v.active then (select a.body from public.venue_announcements a
        where a.venue_id=x.venue_id and a.expires_at>now() order by a.created_at desc limit 1) end
    ) order by x.last_visit desc)
    from (select s.venue_id, count(*)::int as visits, max(s.started_at) as last_visit
          from public.venue_sessions s
          where s.user_id=uid and s.history_hidden_at is null and s.started_at>now()-interval '90 days'
          group by s.venue_id) x
    join private.venues v on v.id=x.venue_id
    where v.category<>'event'), '[]'::jsonb);
end $$;

create or replace function private.hide_place(p_venue uuid) returns jsonb
 language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person(); n int;
begin
  if p_venue is null then raise exception 'invalid_place'; end if;
  update public.venue_sessions set history_hidden_at=now()
   where user_id=uid and venue_id=p_venue and history_hidden_at is null;
  get diagnostics n = row_count;
  return jsonb_build_object('hidden', n);
end $$;

create or replace function private.clear_places() returns jsonb
 language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person(); n int;
begin
  update public.venue_sessions set history_hidden_at=now() where user_id=uid and history_hidden_at is null;
  get diagnostics n = row_count;
  return jsonb_build_object('hidden', n);
end $$;

create or replace function public.my_places() returns jsonb language sql stable set search_path = '' as $$ select private.my_places() $$;
create or replace function public.hide_place(p_venue uuid) returns jsonb language sql set search_path = '' as $$ select private.hide_place(p_venue) $$;
create or replace function public.clear_places() returns jsonb language sql set search_path = '' as $$ select private.clear_places() $$;
revoke all on function private.my_places(), private.hide_place(uuid), private.clear_places(),
  public.my_places(), public.hide_place(uuid), public.clear_places() from public, anon;
grant execute on function private.my_places(), private.hide_place(uuid), private.clear_places() to authenticated;
grant execute on function public.my_places(), public.hide_place(uuid), public.clear_places() to authenticated, service_role;
