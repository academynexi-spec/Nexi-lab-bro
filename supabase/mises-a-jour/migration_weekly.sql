-- NEXI LAB : cycle hebdomadaire (NX de la semaine, défi de la semaine, plafond de mise, mur d'honneur)
-- Sans risque : ne supprime rien, peut être exécuté une seule fois ou plusieurs fois.

alter table profiles add column if not exists wnx int not null default 0 check (wnx>=0);
alter table items add column if not exists weekly bool not null default false;

create table if not exists app_cfg(id int primary key default 1 check (id=1), stake_pct int not null default 25 check (stake_pct between 1 and 100), stake_max int not null default 500 check (stake_max>=1));
insert into app_cfg(id) values (1) on conflict do nothing;
create table if not exists weekly_state(id int primary key default 1 check (id=1), week_start date not null);
insert into weekly_state(id,week_start) values (1,(now() at time zone 'Africa/Lubumbashi')::date) on conflict do nothing;
create table if not exists weekly_archive(
  id bigserial primary key, week_start date not null, week_end date not null,
  user_id uuid references profiles(id) on delete cascade, sector_id int,
  pseudo text, full_name text, wnx int, pos int, active_days int, answers int, accuracy int, gained int,
  badges text[] not null default '{}');
create index if not exists weekly_archive_idx on weekly_archive(week_start, sector_id, pos);
create index if not exists weekly_archive_user on weekly_archive(user_id, week_start desc);

alter table app_cfg enable row level security; alter table weekly_state enable row level security; alter table weekly_archive enable row level security;
drop policy if exists r_appcfg on app_cfg; create policy r_appcfg on app_cfg for select to authenticated using (true);
drop policy if exists w_appcfg on app_cfg; create policy w_appcfg on app_cfg for all to authenticated using (is_admin()) with check (is_admin());
drop policy if exists r_wstate on weekly_state; create policy r_wstate on weekly_state for select to authenticated using (true);
drop policy if exists r_warch on weekly_archive; create policy r_warch on weekly_archive for select to authenticated using (is_admin() or user_id=auth.uid());
drop policy if exists d_warch on weekly_archive; create policy d_warch on weekly_archive for delete to authenticated using (is_admin());

create or replace view items_public as
  select i.id,i.kind,i.category_id,i.palier,i.question,i.options,i.secs,i.factor,i.ord,
         case when i.kind='carte' then i.back end as back,
         i.image, case when i.kind='carte' then i.back_image end as back_image,
         i.weekly
  from items i join categories c on c.id=i.category_id
  where i.published and (is_admin() or c.sector_id=(select sector_id from profiles where id=auth.uid()));
create or replace view leaderboard as
  select p.id,p.pseudo,p.nx,p.sector_id,p.wnx from profiles p
  where p.role='nexian' and (is_admin() or p.sector_id=(select sector_id from profiles where id=auth.uid()));
grant select on items_public, leaderboard to authenticated;

-- Jeu : plafond de mise Nexify + points de la semaine (uniquement pour les questions « Défi de la semaine »)
create or replace function answer_item(p_item bigint, p_choice int, p_ms int, p_stake int default 0) returns json
language plpgsql security definer set search_path=public as $$
declare me profiles; it items; cfg plan_cfg; a int; ok bool; d int:=0; k text; c int; mx int; used int; y int; base int; cap int;
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
  insert into history(user_id,item_id,kind,ok,delta) values(me.id,p_item,it.kind,ok,d);
  return json_build_object('ok',ok,'answer',it.answer,'delta',d,'nx',c,'weekly',it.weekly);
end $$;

-- Mur d'honneur : lauréats des cycles passés dans le secteur du joueur (pseudos seulement)
create or replace function hall() returns table(week_start date, week_end date, pseudo text, wnx int, pos int, badges text[])
language sql security definer stable set search_path=public as $$
  select w.week_start,w.week_end,w.pseudo,w.wnx,w.pos,w.badges from weekly_archive w
  where cardinality(w.badges)>0 and w.sector_id=(select sector_id from profiles where id=auth.uid())
  order by w.week_start desc, w.pos limit 150 $$;

-- Clôture du cycle (admin seulement) : archive, attribue les badges, remet les NX de la semaine à 0
create or replace function close_week() returns json language plpgsql security definer set search_path=public as $$
declare ws date; we date:=(now() at time zone 'Africa/Lubumbashi')::date; n int;
begin
  if not is_admin() then raise exception 'interdit'; end if;
  select week_start into ws from weekly_state where id=1 for update;
  if ws>=we then raise exception 'Le cycle a commencé aujourd''hui : rien à clôturer.'; end if;
  with base as (
    select p.id,p.sector_id,p.pseudo,p.full_name,p.wnx,
           row_number() over(partition by p.sector_id order by p.wnx desc, p.created_at) as pos
    from profiles p where p.role='nexian' and p.sector_id is not null),
  hs as (
    select h.user_id, count(distinct (h.at at time zone 'Africa/Lubumbashi')::date) as days, count(*) as n, count(*) filter (where h.ok) as k
    from history h where (h.at at time zone 'Africa/Lubumbashi')::date>=ws group by h.user_id),
  prev as (select distinct on (a.user_id) a.user_id, a.pos from weekly_archive a order by a.user_id, a.week_start desc)
  insert into weekly_archive(week_start,week_end,user_id,sector_id,pseudo,full_name,wnx,pos,active_days,answers,accuracy,gained)
  select ws,we,b.id,b.sector_id,b.pseudo,b.full_name,b.wnx,b.pos::int,
         coalesce(hs.days,0),coalesce(hs.n,0),
         case when coalesce(hs.n,0)>0 then round(100.0*hs.k/hs.n)::int else 0 end,
         case when prev.pos is null then null else prev.pos-b.pos::int end
  from base b left join hs on hs.user_id=b.id left join prev on prev.user_id=b.id;
  get diagnostics n = row_count;
  -- Or / Argent / Bronze
  update weekly_archive w set badges=w.badges||('top'||w.pos)::text where w.week_start=ws and w.week_end=we and w.pos<=3 and w.wnx>0;
  -- Progression : le plus de places gagnées
  update weekly_archive w set badges=w.badges||'progression'::text from (select distinct on (sector_id) id from weekly_archive where week_start=ws and week_end=we and gained>0 order by sector_id, gained desc, wnx desc) t where w.id=t.id;
  -- Assiduité : le plus de jours actifs (3 minimum)
  update weekly_archive w set badges=w.badges||'assiduite'::text from (select distinct on (sector_id) id from weekly_archive where week_start=ws and week_end=we and active_days>=3 order by sector_id, active_days desc, wnx desc) t where w.id=t.id;
  -- Précision : meilleur taux de réussite (10 réponses minimum)
  update weekly_archive w set badges=w.badges||'precision'::text from (select distinct on (sector_id) id from weekly_archive where week_start=ws and week_end=we and answers>=10 order by sector_id, accuracy desc, answers desc) t where w.id=t.id;
  -- Révélation : meilleur nouveau Nexian (inscrit depuis moins de 30 jours)
  update weekly_archive w set badges=w.badges||'revelation'::text from (select distinct on (a.sector_id) a.id from weekly_archive a join profiles p on p.id=a.user_id where a.week_start=ws and a.week_end=we and a.wnx>0 and p.created_at>now()-interval '30 days' order by a.sector_id, a.wnx desc) t where w.id=t.id;
  update profiles set wnx=0 where role='nexian';
  update weekly_state set week_start=we where id=1;
  return json_build_object('archived',n,'from',ws,'to',we);
end $$;

revoke execute on function hall(), close_week() from public, anon;
grant execute on function hall(), close_week() to authenticated;
