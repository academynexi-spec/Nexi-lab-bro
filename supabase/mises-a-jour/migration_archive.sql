-- NEXI LAB : archivage intelligent (plan gratuit Supabase). Peut être relancé sans danger.
-- Prérequis : schéma de base + migration_weekly + migration_ligues (ou schema.sql complet).
alter table app_cfg add column if not exists keep_days int not null default 90 check (keep_days>=14);
alter table app_cfg add column if not exists emergency bool not null default false;
alter table app_cfg add column if not exists last_maint timestamptz;
alter table app_cfg add column if not exists db_limit_mb int not null default 500 check (db_limit_mb>0);
alter table app_cfg add column if not exists storage_limit_mb int not null default 1024 check (storage_limit_mb>0);
create index if not exists history_at on history(at);
create index if not exists items_cat_palier on items(category_id, palier);

-- Totaux permanents par joueur (ne dépendent plus du détail des parties, qui peut être archivé)
create table if not exists user_stats(user_id uuid primary key references profiles(id) on delete cascade, answers int not null default 0, correct int not null default 0,
  donjon_ok int not null default 0, best_gain int not null default 0, first_at timestamptz, last_at timestamptz);
insert into user_stats(user_id,answers,correct,donjon_ok,best_gain,first_at,last_at)
  select h.user_id,count(*),count(*) filter (where h.ok),count(*) filter (where h.ok and h.kind='donjon'),coalesce(max(h.delta) filter (where h.delta>0),0),min(h.at),max(h.at)
  from history h join profiles p on p.id=h.user_id group by h.user_id on conflict(user_id) do nothing;
-- Résumés mensuels : ce qui reste des parties archivées (jamais supprimé)
create table if not exists history_monthly(user_id uuid references profiles(id) on delete cascade, month date not null, kind text not null,
  answers int not null, correct int not null, delta int not null, primary key(user_id,month,kind));
create table if not exists archive_log(month date primary key, rows int not null, path text not null, at timestamptz not null default now());

alter table user_stats enable row level security; alter table history_monthly enable row level security; alter table archive_log enable row level security;
drop policy if exists r_ustat on user_stats; create policy r_ustat on user_stats for select to authenticated using (is_admin() or user_id=auth.uid());
drop policy if exists r_hmon on history_monthly; create policy r_hmon on history_monthly for select to authenticated using (is_admin() or user_id=auth.uid());
drop policy if exists r_alog on archive_log; create policy r_alog on archive_log for select to authenticated using (is_admin());

-- Archives froides : fichiers compressés dans un bucket privé (stockage séparé de la base), lisibles par l'admin seulement
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('archives','archives',false,52428800,array['application/gzip','text/csv']) on conflict do nothing;
drop policy if exists ar_r on storage.objects; create policy ar_r on storage.objects for select to authenticated using (bucket_id='archives' and is_admin());
drop policy if exists ar_i on storage.objects; create policy ar_i on storage.objects for insert to authenticated with check (bucket_id='archives' and is_admin());
drop policy if exists ar_u on storage.objects; create policy ar_u on storage.objects for update to authenticated using (bucket_id='archives' and is_admin());

-- Interne : résume puis supprime les parties d'une période (les totaux restent dans user_stats et history_monthly)
create or replace function compact_range(b timestamptz, c timestamptz) returns int language plpgsql security definer set search_path=public as $$
declare n int;
begin
  insert into history_monthly(user_id,month,kind,answers,correct,delta)
    select h.user_id, date_trunc('month',h.at at time zone 'Africa/Lubumbashi')::date, h.kind, count(*), count(*) filter (where h.ok), coalesce(sum(h.delta),0)
    from history h where h.at>=b and h.at<c group by 1,2,3
    on conflict(user_id,month,kind) do update set answers=history_monthly.answers+excluded.answers, correct=history_monthly.correct+excluded.correct, delta=history_monthly.delta+excluded.delta;
  delete from history where at>=b and at<c; get diagnostics n=row_count;
  return n;
end $$;

-- Rapport d'utilisation (admin) : taille base, stockage, plus grosses tables, mois à archiver
create or replace function usage_report() returns json language plpgsql security definer set search_path=public as $$
declare cfg app_cfg; dbb bigint; stb bigint; t json; bk json; mths json; cut date; keep int; tz text:='Africa/Lubumbashi';
begin
  if not is_admin() then raise exception 'interdit'; end if;
  select * into cfg from app_cfg where id=1; keep:=cfg.keep_days;
  cut:=date_trunc('month',(now() at time zone tz)-make_interval(days=>keep))::date;
  dbb:=pg_database_size(current_database());
  select coalesce(sum((metadata->>'size')::bigint),0) into stb from storage.objects;
  select coalesce(json_agg(x order by x.bytes desc),'[]'::json) into t from (select c.relname::text as name, pg_total_relation_size(c.oid) as bytes, greatest(c.reltuples,0)::bigint as rows
    from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r') x;
  select coalesce(json_object_agg(q.bucket_id,q.s),'{}'::json) into bk from (select bucket_id, sum(coalesce((metadata->>'size')::bigint,0)) as s from storage.objects group by bucket_id) q;
  select coalesce(json_agg(json_build_object('month',q.m,'rows',q.n) order by q.m),'[]'::json) into mths from
    (select date_trunc('month',h.at at time zone tz)::date as m, count(*) as n from history h where (h.at at time zone tz)::date<cut group by 1) q
    where q.m not in (select month from archive_log);
  return json_build_object('db_bytes',dbb,'storage_bytes',stb,'db_pct',round(100.0*dbb/(cfg.db_limit_mb*1048576.0)),'storage_pct',round(100.0*stb/(cfg.storage_limit_mb*1048576.0)),
    'tables',t,'buckets',bk,'months',mths,'last_maint',cfg.last_maint,'emergency',cfg.emergency,'keep_days',keep);
end $$;

-- Archivage d'un mois : appelé APRÈS l'envoi du fichier. Vérifie le nombre de lignes avant de supprimer quoi que ce soit.
create or replace function archive_commit(p_month date, p_rows int, p_path text) returns json language plpgsql security definer set search_path=public as $$
declare cut date; n int; b timestamptz; c timestamptz; keep int; tz text:='Africa/Lubumbashi';
begin
  if not is_admin() then raise exception 'interdit'; end if;
  select keep_days into keep from app_cfg where id=1;
  cut:=date_trunc('month',(now() at time zone tz)-make_interval(days=>keep))::date;
  if p_month<>date_trunc('month',p_month)::date or p_month>=cut then raise exception 'Ce mois n''est pas encore archivable'; end if;
  b:=p_month::timestamp at time zone tz; c:=(p_month+interval '1 month')::timestamp at time zone tz;
  select count(*) into n from history where at>=b and at<c;
  if n<>p_rows then raise exception 'Le fichier contient % lignes mais la base en compte % : rien n''a été supprimé. Relance l''archivage.',p_rows,n; end if;
  perform compact_range(b,c);
  insert into archive_log(month,rows,path) values(p_month,n,p_path) on conflict(month) do update set rows=excluded.rows,path=excluded.path,at=now();
  return json_build_object('month',p_month,'rows',n);
end $$;

-- Maintenance (admin, ou planifiée par pg_cron) : purge des tickets anciens, mode économie automatique
create or replace function maintenance() returns json language plpgsql security definer set search_path=public as $$
declare cfg app_cfg; dbb bigint; pct numeric; emg bool; purged int:=0; t int; c timestamptz; tz text:='Africa/Lubumbashi';
begin
  if auth.uid() is not null and not is_admin() then raise exception 'interdit'; end if;
  delete from tlog where day < (now() at time zone tz)::date - 3; get diagnostics t=row_count;
  select * into cfg from app_cfg where id=1;
  dbb:=pg_database_size(current_database()); pct:=100.0*dbb/(cfg.db_limit_mb*1048576.0);
  if pct>=90 then
    c:=((now() at time zone tz)::date-30)::timestamp at time zone tz;
    purged:=compact_range('2000-01-01'::timestamptz,c); emg:=true;
  elsif pct<80 then emg:=false; else emg:=cfg.emergency; end if;
  update app_cfg set emergency=emg,last_maint=now() where id=1;
  return json_build_object('tlog',t,'purged',purged,'pct',round(pct,1),'emergency',emg);
end $$;

-- Fichiers de stockage inutilisés (images de questions supprimées, avatars de comptes supprimés)
create or replace function orphan_files() returns json language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'interdit'; end if;
  return (select coalesce(json_agg(json_build_object('bucket',o.bucket_id,'name',o.name,'size',coalesce((o.metadata->>'size')::bigint,0))),'[]'::json)
    from storage.objects o where (o.bucket_id='diagrams' and not exists(select 1 from items i where i.image=o.name or i.back_image=o.name))
      or (o.bucket_id='avatars' and (storage.foldername(o.name))[1] not in (select id::text from profiles)));
end $$;

-- Fonctions mises à jour : réponse (totaux + mode économie) et badges (Centurion lu dans les totaux)
create or replace function award_badges(u uuid) returns text[] language plpgsql security definer set search_path=public as $$
declare p profiles; got text[]; s int;
begin
  select * into p from profiles where id=u; if p.id is null or p.role<>'nexian' then return '{}'; end if;
  select coalesce(max(cnt),0) into s from (select count(*) as cnt from (select dd, dd-(row_number() over(order by dd))::int as g from
    (select distinct (at at time zone 'Africa/Lubumbashi')::date as dd from history where user_id=u) d) x group by g) y;
  with c(code,ok) as (values
    ('premier_pas', exists(select 1 from history where user_id=u)),
    ('explorateur', (select count(distinct i.category_id) from attempts a join items i on i.id=a.item_id where a.user_id=u)>=3),
    ('centurion', coalesce((select correct from user_stats where user_id=u),0)>=100),
    ('serie5', coalesce((select count(*)=5 and bool_and(ok) from (select ok from history where user_id=u order by id desc limit 5) t),false)),
    ('serie10', coalesce((select count(*)=10 and bool_and(ok) from (select ok from history where user_id=u order by id desc limit 10) t),false)),
    ('streak7', s>=7), ('streak30', s>=30),
    ('parieur', coalesce((select count(*)=3 and bool_and(ok) from (select ok from history where user_id=u and kind='nexify' order by id desc limit 3) t),false)),
    ('fidele', (select count(*) from weekly_archive where user_id=u and answers>0)>=4),
    ('podium', exists(select 1 from weekly_archive where user_id=u and pos<=3 and wnx>0)),
    ('rang_d',p.nx>500),('rang_c',p.nx>1000),('rang_b',p.nx>2000),('rang_a',p.nx>5000),('rang_s',p.nx>8000),
    ('rang_elite',p.nx>10500),('rang_prodige',p.nx>25000),('rang_legende',p.nx>50000),('rang_ultra',p.nx>100000)),
  ins as (insert into user_badges(user_id,code) select u,c.code from c where c.ok on conflict do nothing returning code)
  select coalesce(array_agg(code),'{}') into got from ins;
  return got;
end $$;

create or replace function answer_item(p_item bigint, p_choice int, p_ms int, p_stake int default 0) returns json
language plpgsql security definer set search_path=public as $$
declare me profiles; it items; cfg plan_cfg; a int; ok bool; d int:=0; k text; c int; mx int; used int; got text[]; emg bool; y int; base int; cap int;
        today date:=(now() at time zone 'Africa/Lubumbashi')::date;
begin
  select * into me from profiles where id=auth.uid() for update; -- verrou : pas de double envoi simultané
  if me.id is null or me.role<>'nexian' then raise exception 'interdit'; end if;
  if me.plan_end is not null and me.plan_end<today then raise exception 'abonnement expiré'; end if;
  select i.* into it from items i join categories ca on ca.id=i.category_id
    where i.id=p_item and i.published and ca.sector_id=me.sector_id and i.kind<>'carte';
  if it.id is null then raise exception 'question introuvable'; end if;
  select * into cfg from plan_cfg where plan=me.plan;
  if it.kind='nexify' then
    if not cfg.nexify then raise exception 'Nexify est réservé aux formules Premium'; end if;
    select greatest(1,least(floor(me.nx*stake_pct/100.0)::int,stake_max)) into mx from app_cfg where id=1;
    if p_stake<1 or p_stake>me.nx or p_stake>mx then raise exception 'mise invalide (maximum % NX)',mx; end if;
  end if;
  select coalesce(n,0) into a from attempts where user_id=me.id and item_id=p_item;
  if coalesce(a,0)>=cfg.replays then raise exception 'déjà fait'; end if;
  -- ticket : 1 par palier de donjon commencé, 1 par lot de 3 cartes Nexify
  if it.kind='donjon' then k:='d'||it.category_id||'-'||it.palier;
  else select count(*) into c from history where user_id=me.id and kind='nexify' and (at at time zone 'Africa/Lubumbashi')::date=today; k:='n'||(c/3); end if;
  if not exists(select 1 from tlog where user_id=me.id and day=today and key=k) then
    select count(*) into used from tlog where user_id=me.id and day=today;
    base:=coalesce(me.tickets_custom,cfg.tickets); cap:=base;
    if cfg.cumul then select count(*) into y from tlog where user_id=me.id and day=today-1; cap:=base+greatest(base-y,0); end if;
    if used>=cap then raise exception 'plus de tickets aujourd''hui, reviens après minuit'; end if;
    insert into tlog values(me.id,today,k);
  end if;
  ok:= p_choice=it.answer and p_ms<=(it.secs+2)*1000;
  if it.kind='donjon' then
    if ok then d:=it.nx+(case when p_ms<=it.secs*500 then it.bonus else 0 end); end if;
  else d:= case when ok then round(p_stake*(it.factor-1))::int else -p_stake end; end if;
  update profiles set nx=greatest(0,nx+d), wnx=case when it.weekly then greatest(0,wnx+d) else wnx end where id=me.id returning nx into c;
  insert into attempts values(me.id,p_item,1) on conflict(user_id,item_id) do update set n=attempts.n+1;
  select emergency into emg from app_cfg where id=1;
  if not (coalesce(emg,false) and it.kind='donjon') then -- mode économie : on n'écrit plus le détail des donjons
    insert into history(user_id,item_id,kind,ok,delta) values(me.id,p_item,it.kind,ok,d);
  end if;
  insert into user_stats(user_id,answers,correct,donjon_ok,best_gain,first_at,last_at)
    values(me.id,1,case when ok then 1 else 0 end,case when ok and it.kind='donjon' then 1 else 0 end,greatest(d,0),now(),now())
    on conflict(user_id) do update set answers=user_stats.answers+1, correct=user_stats.correct+excluded.correct,
      donjon_ok=user_stats.donjon_ok+excluded.donjon_ok, best_gain=greatest(user_stats.best_gain,excluded.best_gain), last_at=now();
  got:=award_badges(me.id);
  return json_build_object('ok',ok,'answer',it.answer,'delta',d,'nx',c,'weekly',it.weekly,'badges',got);
end $$;

-- Ping anti-pause (le plan gratuit met le projet en veille après 7 jours sans activité) : appelable sans connexion, ne renvoie rien de sensible
create or replace function ping() returns text language sql stable as $$ select 'ok'::text $$;
grant execute on function ping() to anon, authenticated;
revoke execute on function compact_range(timestamptz,timestamptz) from public, anon, authenticated;
revoke execute on function usage_report(), archive_commit(date,int,text), maintenance(), orphan_files() from public, anon;
grant execute on function usage_report(), archive_commit(date,int,text), maintenance(), orphan_files() to authenticated;
-- Optionnel (Database > Extensions > pg_cron activé) : maintenance automatique chaque lundi à 02h :
-- select cron.schedule('nexi-maintenance','0 2 * * 1','select maintenance()');
