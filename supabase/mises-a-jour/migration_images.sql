-- À exécuter UNIQUEMENT si tu as déjà exécuté l'ancien schema.sql (sinon utilise schema.sql seul)
alter table items add column if not exists image text, add column if not exists back_image text;
create or replace view items_public as
  select i.id,i.kind,i.category_id,i.palier,i.question,i.options,i.secs,i.factor,i.ord,
         case when i.kind='carte' then i.back end as back,
         i.image, case when i.kind='carte' then i.back_image end as back_image
  from items i join categories c on c.id=i.category_id
  where i.published and (is_admin() or c.sector_id=(select sector_id from profiles where id=auth.uid()));
grant select on items_public to authenticated;
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

