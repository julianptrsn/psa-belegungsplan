-- Rechnungsnummern je Absender: PSA und Torben Schmidt haben eigene Nummernkreise im Format 2026-97.
-- Dieselbe Nummer darf es daher je einmal bei PSA und bei Torben geben.
-- Außerdem: Absenderdaten Torben Schmidt (aus Rechnung 2026-97). Einmal im Supabase SQL Editor ausführen.

-- 1) Absender auch für importierte Rechnungen festhalten (aus der Wohnung)
create or replace function public.owner_of_unit(u text) returns text
language sql immutable as
$$ select case when u in ('sand-eg','sand-og','vog','ape-ug','ape-eg','ape-og') then 'Torben Schmidt' else 'PSA Immobilien' end $$;

update public.invoices set issuer = public.owner_of_unit(unit_id) where issuer is null and unit_id is not null;

create or replace function public.set_invoice_issuer() returns trigger
language plpgsql as
$$ begin
  if new.source = 'import' and new.unit_id is not null then new.issuer := public.owner_of_unit(new.unit_id); end if;
  return new;
end $$;
drop trigger if exists invoices_set_issuer on public.invoices;
create trigger invoices_set_issuer before insert or update of unit_id on public.invoices
  for each row execute function public.set_invoice_issuer();

-- 2) Eindeutig je Absender statt global
alter table public.invoices drop constraint if exists invoices_number_key;
create unique index if not exists invoices_issuer_number_key on public.invoices (coalesce(issuer,''), number);

-- 3) Nummern ohne führende Nullen (wie bisher in Zervant: 2026-97, 2026-208)
update public.issuers set number_digits = 1;

-- 4) Torben Schmidt: Absenderdaten und Nummernkreis fortsetzen
update public.issuers set
  name = 'Torben Schmidt', contact_name = 'Julian Petersen',
  street = 'Dreschbogen 22', zip = '24943', city = 'Flensburg',
  email = 'info@ma-fl.de', website = 'www.monteurapartments-fl.de',
  vat_id = 'DE814586907', bank = 'Nospa', iban = 'DE61217500000166285544', bic = 'NOLADE21NOS',
  account_holder = 'Torben Schmidt', number_prefix = '', number_year = 2026,
  next_no = greatest(98, coalesce((select max(substring(i.number from '^2026-(\d+)$')::int)+1 from public.invoices i
                                    where i.issuer = 'Torben Schmidt' and i.number ~ '^2026-\d+$'), 1))
where id = 'Torben Schmidt';

-- 5) Standardtext auf jeder Rechnung
alter table public.billing_settings add column if not exists standard_note text not null
  default E'Check-In nach Absprache.\nCheck-Out bis 12:00 Uhr.';

-- 6) Nummernvergabe: nur innerhalb desselben Absenders auf Doppelungen prüfen
create or replace function public.create_invoice(p jsonb) returns public.invoices
language plpgsql security definer set search_path = public as
$$
declare
  iss public.issuers;
  yr int := extract(year from (now() at time zone 'Europe/Berlin'))::int;
  today date := (now() at time zone 'Europe/Berlin')::date;
  n int;
  num text;
  res public.invoices;
begin
  if not public.is_editor() then raise exception 'Keine Bearbeitungsrechte'; end if;
  if not public.can_see_unit(p->>'unit_id') then raise exception 'Keine Rechte für diese Wohnung'; end if;
  if public.owner_of_unit(p->>'unit_id') <> p->>'issuer' then raise exception 'Absender passt nicht zur Wohnung'; end if;
  select * into iss from public.issuers where id = p->>'issuer' for update;
  if not found then raise exception 'Unbekannter Absender'; end if;
  if iss.number_year <> yr then
    update public.issuers set number_year = yr, next_no = 1 where id = iss.id;
    iss.number_year := yr; iss.next_no := 1;
  end if;
  n := iss.next_no;
  loop
    num := iss.number_prefix || yr || '-' || lpad(n::text, greatest(iss.number_digits, length(n::text)), '0');
    exit when not exists (select 1 from public.invoices where number = num and coalesce(issuer,'') = iss.id);
    n := n + 1;
  end loop;
  update public.issuers set next_no = n + 1, updated_at = now() where id = iss.id;

  perform set_config('app.via_rpc', '1', true);
  insert into public.invoices (number, invoice_date, due_date, customer, unit_id, location_text, period_start, period_end,
    quantity, unit_price, vat_rate, net, vat, total, booking_id, is_storno, cancels, source, issuer, issuer_snapshot,
    customer_id, customer_snapshot, lines, lodging_tax, lodging_exempt, lodging_exempt_note, notes)
  values (num, today, today + coalesce((p->>'payment_days')::int, 0), p->>'customer', p->>'unit_id', p->>'location_text',
    (p->>'period_start')::date, (p->>'period_end')::date,
    (p->>'quantity')::numeric, (p->>'unit_price')::numeric, (p->>'vat_rate')::numeric,
    (p->>'net')::numeric, (p->>'vat')::numeric, (p->>'total')::numeric,
    nullif(p->>'booking_id','')::uuid, coalesce((p->>'is_storno')::boolean,false), nullif(p->>'cancels',''),
    'tool', iss.id, to_jsonb(iss) - 'next_no' - 'number_year' - 'updated_at',
    nullif(p->>'customer_id','')::uuid, p->'customer_snapshot', p->'lines',
    (p->>'lodging_tax')::numeric, coalesce((p->>'lodging_exempt')::boolean,false), p->>'lodging_exempt_note', p->>'notes')
  returning * into res;
  perform set_config('app.via_rpc', '', true);
  return res;
end $$;
