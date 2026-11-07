-- ANZIAK migration of 7 November 2026: the product is renamed from P.Rod to ANZIAK (client's choice).
-- Only the operator feedback e-mails carry the product name inside the database. Run once in the Supabase SQL editor.
update private.app_settings set value='"[ANZIAK test] Nouveau retour"' where key='feedback_subject';

CREATE OR REPLACE FUNCTION private.send_feedback_emails()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare api_key text; to_addr text; from_addr text; subj text; f record; n integer := 0; body text; faces text[] := array['😕','😐','🙂','🤩'];
begin
  select decrypted_secret into api_key from vault.decrypted_secrets where name='brevo_api_key' limit 1;
  to_addr := private.setting('feedback_email') #>> '{}'; from_addr := private.setting('feedback_sender') #>> '{}'; subj := coalesce(private.setting('feedback_subject') #>> '{}','[ANZIAK test] Nouveau retour');
  if api_key is null or to_addr is null or from_addr is null then return 0; end if;
  for f in select fb.*, (select display_name from public.profiles p where p.user_id=fb.user_id) as who from public.feedback fb where fb.emailed_at is null order by fb.created_at limit 20 loop
    body := 'Nouveau retour ANZIAK (test)' || E'\n\n' ||
      'Note : ' || coalesce(faces[f.score],'') || ' ' || f.score || '/4' || E'\n' ||
      'Compte : ' || coalesce(f.who,'(supprimé)') || ' · type ' || coalesce(f.account_type,'?') || E'\n' ||
      'Utilisation : ' || coalesce(f.context->>'minutes','?') || ' min · ' || coalesce(f.context->>'lang','') || ' · ' || case when f.context->>'installed'='true' then 'app installée' else 'navigateur' end || ' · écran ' || coalesce(f.context->>'screen','') || E'\n' ||
      'Envoyé le : ' || to_char(f.created_at at time zone 'Europe/Paris','DD/MM/YYYY HH24:MI') || E'\n\n' ||
      'À changer en premier :' || E'\n' || coalesce(f.change_text,'(vide)') || E'\n\n' ||
      case when f.bug then 'BUG signalé :' || E'\n' || coalesce(f.bug_text,'(sans détail)') || E'\n\n' else '' end ||
      'Détail complet dans le portail d’administration, onglet Retours.';
    perform net.http_post(url:='https://api.brevo.com/v3/smtp/email',
      headers:=jsonb_build_object('api-key',api_key,'content-type','application/json','accept','application/json'),
      body:=jsonb_build_object('sender',jsonb_build_object('email',from_addr,'name','ANZIAK test'),'to',jsonb_build_array(jsonb_build_object('email',to_addr)),'subject',subj || ' ' || coalesce(faces[f.score],'') || case when f.bug then ' · bug' else '' end,'textContent',body));
    update public.feedback set emailed_at=now() where id=f.id; n := n+1;
  end loop;
  return n;
end $function$;
