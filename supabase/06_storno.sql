-- Stornorechnungen: Kennzeichen und Verweis auf die stornierte Rechnung
alter table public.invoices
  add column is_storno boolean not null default false,
  add column cancels text;
