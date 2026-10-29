-- Rechnungen: Daten aus hochgeladenen PDFs + Ablage der PDF-Dateien
-- Einmal im Supabase SQL Editor ausführen.

create table public.invoices (
  id uuid primary key default gen_random_uuid(),
  number text not null unique,
  invoice_date date,
  due_date date,
  customer text,
  unit_id text,
  location_text text,
  period_start date,
  period_end date,
  quantity numeric(10,2),
  unit_price numeric(10,2),
  vat_rate numeric(5,2),
  net numeric(10,2),
  vat numeric(10,2),
  total numeric(10,2),
  booking_id uuid references public.bookings(id) on delete set null,
  file_path text,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

alter table public.invoices enable row level security;
create policy "Mitglieder lesen Rechnungen" on public.invoices
  for select to authenticated using (public.is_member());
create policy "Editoren erfassen Rechnungen" on public.invoices
  for insert to authenticated with check (public.is_editor());
create policy "Editoren ändern Rechnungen" on public.invoices
  for update to authenticated using (public.is_editor()) with check (public.is_editor());
create policy "Editoren löschen Rechnungen" on public.invoices
  for delete to authenticated using (public.is_editor());

alter publication supabase_realtime add table public.invoices;

-- Privater Speicherordner für die PDFs (nur PDF, max. 10 MB)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('rechnungen', 'rechnungen', false, 10485760, array['application/pdf']);

create policy "Mitglieder lesen Rechnungs-PDFs" on storage.objects
  for select to authenticated using (bucket_id = 'rechnungen' and public.is_member());
create policy "Editoren laden Rechnungs-PDFs hoch" on storage.objects
  for insert to authenticated with check (bucket_id = 'rechnungen' and public.is_editor());
create policy "Editoren löschen Rechnungs-PDFs" on storage.objects
  for delete to authenticated using (bucket_id = 'rechnungen' and public.is_editor());
