-- Sichtbarkeit pro Eigentümer: Jedes Mitglied sieht nur die Wohnungen der Eigentümer in members.owners.
-- Standard für alle bisherigen Mitglieder: beide Eigentümer (keine Änderung für dich).

-- 1) Wohnungen mit Eigentümer
create table public.units (
  id text primary key,
  owner text not null check (owner in ('PSA Immobilien','Torben Schmidt'))
);
insert into public.units (id, owner) values
  ('afw-og','PSA Immobilien'),('afw-eg','PSA Immobilien'),('afw-ug','PSA Immobilien'),
  ('hain-2r','PSA Immobilien'),('hain-2l','PSA Immobilien'),
  ('h88-1','PSA Immobilien'),('h88-dg','PSA Immobilien'),
  ('h90-1','PSA Immobilien'),('h90-2','PSA Immobilien'),
  ('joh','PSA Immobilien'),('wag-1','PSA Immobilien'),('bee-1','PSA Immobilien'),
  ('ams-2','PSA Immobilien'),('ams-3','PSA Immobilien'),
  ('sand-eg','Torben Schmidt'),('sand-og','Torben Schmidt'),
  ('vog','Torben Schmidt'),
  ('ape-ug','Torben Schmidt'),('ape-eg','Torben Schmidt'),('ape-og','Torben Schmidt');
alter table public.units enable row level security;
create policy "Mitglieder lesen Wohnungen" on public.units
  for select to authenticated using (public.is_member());

-- 2) Pro Mitglied: welche Eigentümer sichtbar sind
alter table public.members
  add column owners text[] not null default array['PSA Immobilien','Torben Schmidt'];

create function public.can_see_unit(u text) returns boolean
language sql stable security definer set search_path = public as
$$ select exists (
     select 1 from members m join units un on un.id = u
     where m.user_id = auth.uid() and un.owner = any(m.owners)) $$;

-- 3) Buchungen nur für sichtbare Wohnungen
drop policy "Mitglieder lesen Buchungen" on public.bookings;
drop policy "Editoren legen an" on public.bookings;
drop policy "Editoren ändern" on public.bookings;
drop policy "Editoren löschen" on public.bookings;
create policy "Buchungen lesen" on public.bookings
  for select to authenticated using (public.can_see_unit(unit_id));
create policy "Buchungen anlegen" on public.bookings
  for insert to authenticated with check (public.is_editor() and public.can_see_unit(unit_id));
create policy "Buchungen ändern" on public.bookings
  for update to authenticated
  using (public.is_editor() and public.can_see_unit(unit_id))
  with check (public.is_editor() and public.can_see_unit(unit_id));
create policy "Buchungen löschen" on public.bookings
  for delete to authenticated using (public.is_editor() and public.can_see_unit(unit_id));

-- 4) Rechnungen nur für sichtbare Wohnungen
drop policy "Mitglieder lesen Rechnungen" on public.invoices;
drop policy "Editoren erfassen Rechnungen" on public.invoices;
drop policy "Editoren ändern Rechnungen" on public.invoices;
drop policy "Editoren löschen Rechnungen" on public.invoices;
create policy "Rechnungen lesen" on public.invoices
  for select to authenticated using (public.can_see_unit(unit_id));
create policy "Rechnungen erfassen" on public.invoices
  for insert to authenticated with check (public.is_editor() and public.can_see_unit(unit_id));
create policy "Rechnungen ändern" on public.invoices
  for update to authenticated
  using (public.is_editor() and public.can_see_unit(unit_id))
  with check (public.is_editor() and public.can_see_unit(unit_id));
create policy "Rechnungen löschen" on public.invoices
  for delete to authenticated using (public.is_editor() and public.can_see_unit(unit_id));

-- 5) Rechnungs-PDFs nur, wenn die zugehörige Rechnung sichtbar ist
drop policy "Mitglieder lesen Rechnungs-PDFs" on storage.objects;
create policy "Rechnungs-PDFs lesen" on storage.objects
  for select to authenticated using (
    bucket_id = 'rechnungen'
    and exists (select 1 from public.invoices i
                where i.file_path = storage.objects.name and public.can_see_unit(i.unit_id)));
