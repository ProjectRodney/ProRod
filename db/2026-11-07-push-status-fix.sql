-- ANZIAK fix of 7 November 2026 (found by database check 8b): push_status() called require_member() inside a count, so with
-- no saved device the check never ran and an unconfirmed account got {"devices":0} instead of verified_account_required.
-- Nothing private was exposed (a count of zero), but the rule must hold. Run once in the SQL editor, then section 8b again.
create or replace function private.push_status() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_member();  -- checked first, whatever the table holds
begin
  return jsonb_build_object('devices',(select count(*) from public.push_subscriptions where user_id=uid));
end $$;
