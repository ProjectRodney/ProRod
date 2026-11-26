-- Read-only: gives the content of db/functions.sql (every function of the schemas private and public, then their grants)
-- as one cell. Run in the SQL editor, export as CSV, and replace everything below the header of db/functions.sql.
select string_agg(def, E'\n\n' order by ord, name) as functions_sql
from (
  select 1 as ord, n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as name,
         pg_get_functiondef(p.oid) || ';' as def
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname in ('private','public') and p.prokind = 'f'
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  union all
  select 2, n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' || a.grantee::regrole::text,
         'grant execute on function ' || n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ') to ' || a.grantee::regrole::text || ';'
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  cross join lateral aclexplode(p.proacl) a
  where n.nspname in ('private','public') and p.prokind = 'f' and a.privilege_type = 'EXECUTE'
    and a.grantee <> 0 and a.grantee::regrole::text in ('anon','authenticated','service_role')
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
) x;
