-- Feedback on demand (client request, 14 November 2026): every feedback is kept in the administration portal;
-- a button sends them all, grouped in one e-mail, to the address in the setting feedback_email.
-- The e-mail sent for each feedback as it arrives is switched off by the setting feedback_auto_email.
--   Back on: update private.app_settings set value='true', updated_at=now() where key='feedback_auto_email';
begin;

insert into private.app_settings(key,value) values ('feedback_auto_email','false')
on conflict (key) do update set value='false', updated_at=now();
update private.app_settings set value='"[UPZONE] Nouveau retour"', updated_at=now() where key='feedback_subject';

CREATE OR REPLACE FUNCTION private.send_feedback_emails()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare api_key text; to_addr text; from_addr text; subj text; f record; n integer := 0; body text; faces text[] := array['😕','😐','🙂','🤩'];
begin
  select decrypted_secret into api_key from vault.decrypted_secrets where name='brevo_api_key' limit 1;
  to_addr := private.setting('feedback_email') #>> '{}'; from_addr := private.setting('feedback_sender') #>> '{}'; subj := coalesce(private.setting('feedback_subject') #>> '{}','[UPZONE] Nouveau retour');
  if coalesce(private.setting('feedback_auto_email'),'true'::jsonb) = 'false'::jsonb then return 0; end if;
  if api_key is null or to_addr is null or from_addr is null then return 0; end if;
  for f in select fb.*, (select display_name from public.profiles p where p.user_id=fb.user_id) as who from public.feedback fb where fb.emailed_at is null order by fb.created_at limit 20 loop
    body := 'Nouveau retour UPZONE' || E'\n\n' ||
      'Note : ' || coalesce(faces[f.score],'') || ' ' || f.score || '/4' || E'\n' ||
      'Compte : ' || coalesce(f.who,'(supprimé)') || ' · type ' || coalesce(f.account_type,'?') || E'\n' ||
      'Utilisation : ' || coalesce(f.context->>'minutes','?') || ' min · ' || coalesce(f.context->>'lang','') || ' · ' || case when f.context->>'installed'='true' then 'app installée' else 'navigateur' end || ' · écran ' || coalesce(f.context->>'screen','') || E'\n' ||
      'Envoyé le : ' || to_char(f.created_at at time zone 'Europe/Paris','DD/MM/YYYY HH24:MI') || E'\n\n' ||
      'À changer en premier :' || E'\n' || coalesce(f.change_text,'(vide)') || E'\n\n' ||
      case when f.bug then 'BUG signalé :' || E'\n' || coalesce(f.bug_text,'(sans détail)') || E'\n\n' else '' end ||
      'Détail complet dans le portail d’administration, onglet Retours.';
    perform net.http_post(url:='https://api.brevo.com/v3/smtp/email',
      headers:=jsonb_build_object('api-key',api_key,'content-type','application/json','accept','application/json'),
      body:=jsonb_build_object('sender',jsonb_build_object('email',from_addr,'name','UPZONE'),'to',jsonb_build_array(jsonb_build_object('email',to_addr)),'subject',subj || ' ' || coalesce(faces[f.score],'') || case when f.bug then ' · bug' else '' end,'textContent',body));
    update public.feedback set emailed_at=now() where id=f.id; n := n+1;
  end loop;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION private.admin_send_feedback(p_hours integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin(); api_key text; to_addr text; from_addr text; n integer; avg_score numeric; bugs integer; body text; period text; ids uuid[];
begin
  if p_hours is not null and p_hours not between 1 and 8760 then raise exception 'invalid_duration'; end if;
  select decrypted_secret into api_key from vault.decrypted_secrets where name='brevo_api_key' limit 1;
  to_addr := private.setting('feedback_email') #>> '{}'; from_addr := private.setting('feedback_sender') #>> '{}';
  if api_key is null or to_addr is null or from_addr is null then raise exception 'feedback_email_not_configured'; end if;
  select array_agg(id) into ids from (select f.id from public.feedback f
    where p_hours is null or f.created_at > now() - make_interval(hours => p_hours) order by f.created_at desc limit 300) picked;
  n := coalesce(array_length(ids,1),0);
  if n = 0 then return jsonb_build_object('count',0); end if;
  select round(avg(score),1), count(*) filter (where bug) into avg_score, bugs from public.feedback where id = any(ids);
  period := case when p_hours is null then 'Tous les retours' else 'Retours des ' || p_hours || ' dernières heures' end;
  select 'UPZONE · retours des membres' || E'\n' || period || ' · envoyé le ' || to_char(now() at time zone 'Europe/Paris','DD/MM/YYYY HH24:MI') || E'\n' ||
         n || ' retour(s) · note moyenne ' || avg_score || '/4 · ' || bugs || ' bug(s) signalé(s)' || E'\n\n' ||
         string_agg(
           '— Retour ' || rn || ' · ' || to_char(created_at at time zone 'Europe/Paris','DD/MM/YYYY HH24:MI') || ' —' || E'\n' ||
           'Note : ' || score || '/4' || E'\n' ||
           'Compte : ' || coalesce(who,'(supprimé)') || ' · type ' || coalesce(account_type,'?') || E'\n' ||
           'Utilisation : ' || coalesce(context->>'minutes','?') || ' min · ' || case when context->>'installed'='true' then 'application installée' else 'navigateur' end || E'\n' ||
           case when change_text is not null then 'À changer en premier : ' || change_text || E'\n' else '' end ||
           case when bug then 'Bug : ' || coalesce(bug_text,'signalé sans détail') || E'\n' else '' end,
           E'\n' order by created_at)
    into body from (select f.*, (select display_name from public.profiles p where p.user_id=f.user_id) as who, row_number() over (order by f.created_at) as rn
                    from public.feedback f where f.id = any(ids)) x;
  perform net.http_post(url:='https://api.brevo.com/v3/smtp/email',
    headers:=jsonb_build_object('api-key',api_key,'content-type','application/json','accept','application/json'),
    body:=jsonb_build_object('sender',jsonb_build_object('email',from_addr,'name','UPZONE'),'to',jsonb_build_array(jsonb_build_object('email',to_addr)),'subject','[UPZONE] Retours regroupés (' || n || ')','textContent',body));
  update public.feedback set emailed_at=now() where emailed_at is null and id = any(ids);
  perform private.log_admin(uid,'feedback_sent',null,jsonb_build_object('count',n,'hours',p_hours));
  return jsonb_build_object('count',n,'to',to_addr);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_send_feedback(p_hours integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_send_feedback(p_hours) $function$;

revoke all on function private.admin_send_feedback(integer) from public, anon;
revoke all on function public.admin_send_feedback(integer) from public, anon;
grant execute on function private.admin_send_feedback(integer) to authenticated;
grant execute on function public.admin_send_feedback(integer) to authenticated, service_role;

commit;

select 'Feedback on demand installed' as result;
