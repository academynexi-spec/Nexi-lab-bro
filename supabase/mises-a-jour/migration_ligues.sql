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
