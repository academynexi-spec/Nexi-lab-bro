-- NEXI LAB : à exécuter en entier dans Supabase > SQL Editor
create extension if not exists pgcrypto with schema extensions;

create table sectors(id serial primary key, name text unique not null);
insert into sectors(name) values ('Génie Civil'),('Génie Mécanique'),('Génie Électrique'),('Génie Chimique'),('Génie Métallurgique'),('Génie Minier'),('Génie Industriel'),('Génie Énergétique'),('Génie Informatique'),('Génie des Matériaux'),('Génie de l''Environnement'),('Génie Biomédical'),('Génie Aérospatial'),('Génie des Télécommunications'),('Génie Architectural'),('Génie Géologique');

create table categories(id serial primary key, sector_id int not null references sectors on delete cascade, name text not null, unique(sector_id,name));

create table plan_cfg(plan text primary key, tickets int not null, nexify bool not null, replays int not null, cumul bool not null default false);
insert into plan_cfg values ('freemium',3,false,1,false),('standard',50,true,1,false),('pro',150,true,1,true),('full',1000000,true,2,false);

create table profiles(
  id uuid primary key references auth.users on delete cascade,
  login text unique not null, full_name text not null, pseudo text unique not null,
  role text not null default 'nexian' check (role in ('nexian','admin')),
  sector_id int references sectors, sex text,
  plan text not null default 'freemium' references plan_cfg,
  plan_start date default current_date, plan_end date, tickets_custom int,
  nx int not null default 100 check (nx>=0), avatar_url text, created_at timestamptz default now());

create table items(
  id bigserial primary key, kind text not null check (kind in ('donjon','nexify','carte')),
  category_id int not null references categories on delete cascade, palier int not null default 1,
  question text not null, options text[], answer int, secs int default 20, nx int default 10,
  bonus int default 5, factor numeric default 2, back text, image text, back_image text, published bool not null default true, ord serial);
create index on items(kind,category_id,palier);

create table attempts(user_id uuid references profiles on delete cascade, item_id bigint references items on delete cascade, n int not null default 0, primary key(user_id,item_id));
create table tlog(user_id uuid references profiles on delete cascade, day date, key text, primary key(user_id,day,key));
create table history(id bigserial primary key, user_id uuid references profiles on delete cascade, item_id bigint, kind text, ok bool, delta int, at timestamptz default now());

create function is_admin() returns bool language sql security definer set search_path=public stable as
$$ select exists(select 1 from profiles where id=auth.uid() and role='admin') $$;

-- RLS
alter table sectors enable row level security; alter table categories enable row level security;
alter table plan_cfg enable row level security; alter table profiles enable row level security;
alter table items enable row level security; alter table attempts enable row level security;
alter table tlog enable row level security; alter table history enable row level security;

create policy r_sectors on sectors for select to authenticated using (true);
create policy r_cat on categories for select to authenticated using (true);
create policy r_cfg on plan_cfg for select to authenticated using (true);
create policy w_sectors on sectors for all to authenticated using (is_admin()) with check (is_admin());
create policy w_cat on categories for all to authenticated using (is_admin()) with check (is_admin());
create policy w_cfg on plan_cfg for all to authenticated using (is_admin()) with check (is_admin());
create policy p_read on profiles for select to authenticated using (id=auth.uid() or is_admin());
create policy p_admin on profiles for all to authenticated using (is_admin()) with check (is_admin());
create policy i_admin on items for all to authenticated using (is_admin()) with check (is_admin());
create policy a_read on attempts for select to authenticated using (user_id=auth.uid() or is_admin());
create policy t_read on tlog for select to authenticated using (user_id=auth.uid() or is_admin());
create policy h_read on history for select to authenticated using (user_id=auth.uid() or is_admin());

-- Vues publiques (sans la bonne réponse), limitées au secteur du joueur
create view items_public as
  select i.id,i.kind,i.category_id,i.palier,i.question,i.options,i.secs,i.factor,i.ord,
         case when i.kind='carte' then i.back end as back,
         i.image, case when i.kind='carte' then i.back_image end as back_image
  from items i join categories c on c.id=i.category_id
  where i.published and (is_admin() or c.sector_id=(select sector_id from profiles where id=auth.uid()));
create view leaderboard as
  select p.id,p.pseudo,p.nx,p.sector_id from profiles p
  where p.role='nexian' and (is_admin() or p.sector_id=(select sector_id from profiles where id=auth.uid()));
revoke all on items_public, leaderboard from anon;
grant select on items_public, leaderboard to authenticated;

-- Profil : le joueur ne change que pseudo et photo
create function set_profile(p_pseudo text, p_avatar text) returns void language sql security definer set search_path=public as
$$ update profiles set pseudo=left(trim(p_pseudo),20), avatar_url=p_avatar where id=auth.uid() and length(trim(p_pseudo))>=2 $$;

create function admin_set_password(p_id uuid, p_pw text) returns void language plpgsql security definer set search_path=public,extensions as
$$ begin
  if not is_admin() then raise exception 'interdit'; end if;
  if length(p_pw)<6 then raise exception 'mot de passe trop court (6 min.)'; end if;
  update auth.users set encrypted_password=crypt(p_pw,gen_salt('bf')), updated_at=now() where id=p_id;
end $$;

-- Cœur du jeu : toute la logique (tickets, minuit, tentatives, gains) est côté serveur
-- Le jour change à minuit heure de Lubumbashi, calculé par le serveur : changer l'heure du téléphone ne sert à rien.
create function answer_item(p_item bigint, p_choice int, p_ms int, p_stake int default 0) returns json
language plpgsql security definer set search_path=public as $$
declare me profiles; it items; cfg plan_cfg; a int; ok bool; d int:=0; k text; c int; used int; y int; base int; cap int;
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
    if p_stake<1 or p_stake>me.nx then raise exception 'mise invalide'; end if;
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
  update profiles set nx=greatest(0,nx+d) where id=me.id returning nx into c;
  insert into attempts values(me.id,p_item,1) on conflict(user_id,item_id) do update set n=attempts.n+1;
  insert into history(user_id,item_id,kind,ok,delta) values(me.id,p_item,it.kind,ok,d);
  return json_build_object('ok',ok,'answer',it.answer,'delta',d,'nx',c);
end $$;

-- Photos de profil
insert into storage.buckets(id,name,public) values('avatars','avatars',true) on conflict do nothing;
create policy av_read on storage.objects for select using (bucket_id='avatars');
create policy av_ins on storage.objects for insert to authenticated with check (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);
create policy av_upd on storage.objects for update to authenticated using (bucket_id='avatars' and (storage.foldername(name))[1]=auth.uid()::text);

-- Schémas (flowsheets, schémas électriques, dessins industriels) : bucket PRIVÉ, lecture pour les connectés, écriture admin seulement
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('diagrams','diagrams',false,5242880,array['image/png','image/jpeg','image/webp']) on conflict do nothing;
create policy dg_read on storage.objects for select to authenticated using (bucket_id='diagrams');
create policy dg_ins on storage.objects for insert to authenticated with check (bucket_id='diagrams' and is_admin());
create policy dg_upd on storage.objects for update to authenticated using (bucket_id='diagrams' and is_admin());
create policy dg_del on storage.objects for delete to authenticated using (bucket_id='diagrams' and is_admin());
-- L'admin peut réactiver une question (effacer les tentatives) ; index de performance
create policy a_admin_del on attempts for delete to authenticated using (is_admin());
create index on history(user_id, at desc);
create index on profiles(sector_id, nx desc);

-- PREMIER ADMIN : crée d'abord admin@nexilab.app dans Authentication > Users, puis exécute :
-- insert into profiles(id,login,full_name,pseudo,role) select id,'admin','Administrateur','admin','admin' from auth.users where email='admin@nexilab.app';

-- ===== CYCLE HEBDOMADAIRE (inclus pour une nouvelle installation) =====
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

-- NEXI LAB : ligues, badges permanents, chapeaux (mini-concours). Peut être relancé sans danger.
-- Prérequis : migration_weekly.sql déjà exécutée (ou schema.sql complet).
alter table profiles add column if not exists league int not null default 1 check (league between 1 and 5);
alter table weekly_archive add column if not exists league int;
alter table weekly_archive add column if not exists move int;

-- LIGUES : activables secteur par secteur. 'promo' = promotion/relégation (tout le monde démarre Bronze), 'rang' = ligue selon le rang NX
create table if not exists league_cfg(sector_id int primary key references sectors(id) on delete cascade, enabled bool not null default false, mode text not null default 'promo' check (mode in ('promo','rang')));
create or replace function rank_league(n int) returns int language sql immutable as $$ select case when n<=1000 then 1 when n<=5000 then 2 when n<=10500 then 3 else 4 end $$;
create or replace function lg_eff(sec int, lg int, n int) returns int language sql stable security definer set search_path=public as $$
  select coalesce((select case when c.enabled then case when c.mode='rang' then rank_league(n) else lg end else 0 end from league_cfg c where c.sector_id=sec),0) $$;
create or replace view leaderboard as
  select p.id,p.pseudo,p.nx,p.sector_id,p.wnx,lg_eff(p.sector_id,p.league,p.nx) as lg from profiles p
  where p.role='nexian' and (is_admin() or p.sector_id=(select sector_id from profiles where id=auth.uid()));
grant select on leaderboard to authenticated;

-- BADGES PERMANENTS (attribués par le serveur uniquement)
create table if not exists badge_defs(code text primary key, name text not null, icon text not null, descr text not null, sort int not null default 0);
create table if not exists user_badges(user_id uuid references profiles(id) on delete cascade, code text references badge_defs(code) on delete cascade, at timestamptz not null default now(), primary key(user_id,code));
insert into badge_defs(code,name,icon,descr,sort) values
 ('premier_pas','Premier pas','👣','Répondre à ta première question',1),
 ('explorateur','Explorateur','🧭','Jouer dans 3 catégories différentes',2),
 ('centurion','Centurion','💯','100 bonnes réponses au total',3),
 ('serie5','Sans faute ×5','✨','5 bonnes réponses d’affilée',4),
 ('serie10','Imparable ×10','⚡','10 bonnes réponses d’affilée',5),
 ('streak7','Semaine de feu','🔥','7 jours d’activité d’affilée',6),
 ('streak30','Mois de fer','🛡️','30 jours d’activité d’affilée',7),
 ('parieur','Parieur','🎰','3 cartes Nexify gagnées d’affilée',8),
 ('fidele','Fidèle','🤝','Actif pendant 4 cycles hebdomadaires',9),
 ('podium','Podium','🥇','Terminer dans le top 3 d’un cycle',10),
 ('chapeau','Champion de chapeau','🎩','Gagner un mini-concours',11),
 ('rang_d','Rang D','🔹','Atteindre le rang D',20),('rang_c','Rang C','🔷','Atteindre le rang C',21),
 ('rang_b','Rang B','🟦','Atteindre le rang B',22),('rang_a','Rang A','🟪','Atteindre le rang A',23),
 ('rang_s','Rang S','🟧','Atteindre le rang S',24),('rang_elite','Élite','💎','Atteindre le rang Élite',25),
 ('rang_prodige','Prodige','🌠','Atteindre le rang Prodige',26),('rang_legende','Légende','🐉','Atteindre le rang Légende',27),
 ('rang_ultra','Ultra Nexian','👑','Atteindre le rang Ultra Nexian',28)
on conflict(code) do update set name=excluded.name,icon=excluded.icon,descr=excluded.descr,sort=excluded.sort;

create or replace function award_badges(u uuid) returns text[] language plpgsql security definer set search_path=public as $$
declare p profiles; got text[]; s int;
begin
  select * into p from profiles where id=u; if p.id is null or p.role<>'nexian' then return '{}'; end if;
  select coalesce(max(cnt),0) into s from (select count(*) as cnt from (select dd, dd-(row_number() over(order by dd))::int as g from
    (select distinct (at at time zone 'Africa/Lubumbashi')::date as dd from history where user_id=u) d) x group by g) y;
  with c(code,ok) as (values
    ('premier_pas', exists(select 1 from history where user_id=u)),
    ('explorateur', (select count(distinct i.category_id) from attempts a join items i on i.id=a.item_id where a.user_id=u)>=3),
    ('centurion', (select count(*) from history where user_id=u and ok)>=100),
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

-- CHAPEAUX : groupes choisis par l'admin pour un mini-concours (classement propre aux membres)
create table if not exists hats(id bigserial primary key, name text not null, note text, sector_id int references sectors(id) on delete set null,
  category_id int references categories(id) on delete set null, starts_at timestamptz not null default now(), ends_at timestamptz, closed bool not null default false);
create table if not exists hat_members(hat_id bigint references hats(id) on delete cascade, user_id uuid references profiles(id) on delete cascade, primary key(hat_id,user_id));
create or replace function hat_board(p_hat bigint) returns table(user_id uuid, pseudo text, full_name text, score int, answers int)
language sql security definer stable set search_path=public as $$
  select m.user_id, p.pseudo, case when is_admin() then p.full_name end, coalesce(sum(h.delta),0)::int, count(h.id)::int
  from hats t join hat_members m on m.hat_id=t.id join profiles p on p.id=m.user_id
  left join history h on h.user_id=m.user_id and h.at>=t.starts_at and (t.ends_at is null or h.at<=t.ends_at)
       and (t.category_id is null or exists(select 1 from items i where i.id=h.item_id and i.category_id=t.category_id))
  where t.id=p_hat and (is_admin() or exists(select 1 from hat_members x where x.hat_id=t.id and x.user_id=auth.uid()))
  group by m.user_id,p.pseudo,p.full_name order by 4 desc,5 desc,2 $$;
create or replace function close_hat(p_hat bigint) returns json language plpgsql security definer set search_path=public as $$
declare t hats;
begin
  if not is_admin() then raise exception 'interdit'; end if;
  select * into t from hats where id=p_hat for update;
  if t.id is null then raise exception 'chapeau introuvable'; end if;
  if t.closed then raise exception 'Ce chapeau est déjà clôturé'; end if;
  update hats set ends_at=now(), closed=true where id=p_hat;
  insert into user_badges(user_id,code) select b.user_id,'chapeau' from hat_board(p_hat) b where b.score>0 order by b.score desc limit 1 on conflict do nothing;
  return (select coalesce(json_agg(json_build_object('pseudo',x.pseudo,'full_name',x.full_name,'score',x.score)),'[]'::json) from (select * from hat_board(p_hat) limit 3) x);
end $$;

-- SÉCURITÉ
alter table league_cfg enable row level security; alter table badge_defs enable row level security; alter table user_badges enable row level security;
alter table hats enable row level security; alter table hat_members enable row level security;
drop policy if exists r_lcfg on league_cfg; create policy r_lcfg on league_cfg for select to authenticated using (true);
drop policy if exists w_lcfg on league_cfg; create policy w_lcfg on league_cfg for all to authenticated using (is_admin()) with check (is_admin());
drop policy if exists r_bdef on badge_defs; create policy r_bdef on badge_defs for select to authenticated using (true);
drop policy if exists r_ubad on user_badges; create policy r_ubad on user_badges for select to authenticated using (is_admin() or user_id=auth.uid());
drop policy if exists r_hats on hats; create policy r_hats on hats for select to authenticated using (is_admin() or exists(select 1 from hat_members m where m.hat_id=hats.id and m.user_id=auth.uid()));
drop policy if exists w_hats on hats; create policy w_hats on hats for all to authenticated using (is_admin()) with check (is_admin());
drop policy if exists r_hmem on hat_members; create policy r_hmem on hat_members for select to authenticated using (is_admin() or user_id=auth.uid());
drop policy if exists w_hmem on hat_members; create policy w_hmem on hat_members for all to authenticated using (is_admin()) with check (is_admin());

-- Fonctions mises à jour : réponse (badges) et clôture du cycle (ligues + badges)
create or replace function answer_item(p_item bigint, p_choice int, p_ms int, p_stake int default 0) returns json
language plpgsql security definer set search_path=public as $$
declare me profiles; it items; cfg plan_cfg; a int; ok bool; d int:=0; k text; c int; mx int; used int; got text[]; y int; base int; cap int;
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
  got:=award_badges(me.id);
  return json_build_object('ok',ok,'answer',it.answer,'delta',d,'nx',c,'weekly',it.weekly,'badges',got);
end $$;

create or replace function close_week() returns json language plpgsql security definer set search_path=public as $$
declare ws date; we date:=(now() at time zone 'Africa/Lubumbashi')::date; n int;
begin
  if not is_admin() then raise exception 'interdit'; end if;
  select week_start into ws from weekly_state where id=1 for update;
  if ws>=we then raise exception 'Le cycle a commencé aujourd''hui : rien à clôturer.'; end if;
  with base as (
    select p.id,p.sector_id,p.pseudo,p.full_name,p.wnx,
           row_number() over(partition by p.sector_id, lg_eff(p.sector_id,p.league,p.nx) order by p.wnx desc, p.created_at) as pos
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
  -- Ligues : ligue de la semaine archivée, puis promotion / relégation (secteurs en modèle « promotion »)
  update weekly_archive w set league=lg_eff(w.sector_id,p.league,p.nx) from profiles p where p.id=w.user_id and w.week_start=ws and w.week_end=we;
  with c as (select sector_id from league_cfg where enabled and mode='promo'),
  r as (select p.id,p.league,p.wnx,count(*) over(partition by p.sector_id,p.league) as cnt,
               row_number() over(partition by p.sector_id,p.league order by p.wnx desc,p.nx desc,p.created_at) as rk
        from profiles p join c on c.sector_id=p.sector_id where p.role='nexian'),
  m as (select id, case when cnt>=4 and rk<=cnt/4 and wnx>0 and league<5 then 1
                        when cnt>=4 and rk>cnt-cnt/4 and league>1 then -1 else 0 end as mv from r),
  a as (update weekly_archive w set move=m.mv from m where w.user_id=m.id and w.week_start=ws and w.week_end=we returning 1)
  update profiles p set league=p.league+m.mv from m where p.id=m.id and m.mv<>0;
  update profiles set wnx=0 where role='nexian';
  perform award_badges(id) from profiles where role='nexian';
  update weekly_state set week_start=we where id=1;
  return json_build_object('archived',n,'from',ws,'to',we);
end $$;

revoke execute on function award_badges(uuid), close_hat(bigint) from public, anon, authenticated;
grant execute on function close_hat(bigint) to authenticated;
revoke execute on function hat_board(bigint) from public, anon;
grant execute on function hat_board(bigint) to authenticated;

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
