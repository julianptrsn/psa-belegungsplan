-- Rechnungspositionen für die Statistik "Hauptprodukte und Dienstleistungen"
alter table public.invoices add column positions jsonb;
