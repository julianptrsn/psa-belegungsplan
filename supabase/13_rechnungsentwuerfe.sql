-- Rechnungsentwürfe: gespeichert ohne Rechnungsnummer, frei änderbar und löschbar.
-- Erst beim Fertigstellen entsteht über create_invoice eine echte Rechnung mit Nummer (GoBD).
-- Kann gefahrlos mehrfach ausgeführt werden.

create table if not exists public.invoice_drafts (
  id            uuid primary key default gen_random_uuid(),
  unit_id       text,
  customer_id   uuid references public.customers(id) on delete set null,
  booking_id    uuid references public.bookings(id) on delete set null,
  customer      text,
  period_start  date,
  period_end    date,
  total         numeric(12,2),
  data          jsonb not null default '{}'::jsonb,
  created_by    uuid default auth.uid(),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

alter table public.invoice_drafts enable row level security;

drop policy if exists "Entwürfe lesen"   on public.invoice_drafts;
drop policy if exists "Entwürfe anlegen" on public.invoice_drafts;
drop policy if exists "Entwürfe ändern"  on public.invoice_drafts;
drop policy if exists "Entwürfe löschen" on public.invoice_drafts;

create policy "Entwürfe lesen" on public.invoice_drafts
  for select to authenticated using (public.is_member() and (unit_id is null or public.can_see_unit(unit_id)));
create policy "Entwürfe anlegen" on public.invoice_drafts
  for insert to authenticated with check (public.is_editor());
create policy "Entwürfe ändern" on public.invoice_drafts
  for update to authenticated using (public.is_editor()) with check (public.is_editor());
create policy "Entwürfe löschen" on public.invoice_drafts
  for delete to authenticated using (public.is_editor());

grant select, insert, update, delete on public.invoice_drafts to authenticated;
