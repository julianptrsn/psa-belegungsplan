-- Rechnungsstellung im Tool: Kunden, Absender (PSA / Torben), Einstellungen,
-- fortlaufende Rechnungsnummern und Schutz geschriebener Rechnungen (GoBD).
-- Einmal im Supabase SQL Editor ausführen.

-- 1) Kunden ---------------------------------------------------------------
create table public.customers (
  id uuid primary key default gen_random_uuid(),
  customer_no text unique,
  kind text not null default 'company' check (kind in ('company','private')),
  company_name text not null default '',
  tax_number text default '',
  vat_id text default '',
  first_name text default '',
  last_name text default '',
  phone text default '',
  emails text[] not null default '{}' check (cardinality(emails) <= 3),
  street text default '',
  street2 text default '',
  zip text default '',
  city text default '',
  country text not null default 'DE',
  language text not null default 'de' check (language in ('de','en')),
  payment_days int not null default 3 check (payment_days between 0 and 120),
  leitweg_id text default '',
  lodging_exempt boolean not null default false,
  lodging_exempt_note text default '',
  notes text default '',
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid()
);
alter table public.customers enable row level security;
create policy "Kunden lesen" on public.customers for select to authenticated using (public.is_member());
create policy "Kunden anlegen" on public.customers for insert to authenticated with check (public.is_editor());
create policy "Kunden ändern" on public.customers for update to authenticated using (public.is_editor()) with check (public.is_editor());
create policy "Kunden löschen" on public.customers for delete to authenticated using (public.is_editor());
create trigger customers_touch before update on public.customers
  for each row execute function public.touch_booking();
alter publication supabase_realtime add table public.customers;

-- 2) Absender je Eigentümer, mit eigenem Nummernkreis ---------------------
create table public.issuers (
  id text primary key check (id in ('PSA Immobilien','Torben Schmidt')),
  name text not null default '',
  contact_name text default '',
  street text default '',
  zip text default '',
  city text default '',
  email text default '',
  phone text default '',
  website text default '',
  tax_number text default '',
  vat_id text default '',
  register_no text default '',
  register_court text default '',
  bank text default '',
  iban text default '',
  bic text default '',
  account_holder text default '',
  number_prefix text not null default '',
  number_year int not null default extract(year from now())::int,
  next_no int not null default 1 check (next_no > 0),
  number_digits int not null default 3 check (number_digits between 1 and 6),
  updated_at timestamptz not null default now()
);
alter table public.issuers enable row level security;
create policy "Absender lesen" on public.issuers for select to authenticated using (public.is_member());
create policy "Absender ändern" on public.issuers for update to authenticated using (public.is_editor()) with check (public.is_editor());

insert into public.issuers (id,name,contact_name,street,zip,city,email,website,tax_number,vat_id,register_no,register_court,bank,iban,bic,account_holder,number_prefix,number_year,next_no)
values
 ('PSA Immobilien','PSA Immobilien GmbH','Julian Petersen','Gewerbedamm 4','24955','Harrislee','info@ma-fl.de','www.monteurapartments-fl.de',
  '15/290/37365','DE408602426','HRB 15864 FL','Amtsgericht Flensburg','Nord-Ostsee Sparkasse','DE60217500000166171975','NOLADE21NOS','PSA Immobilien GmbH',
  '',2026,
  greatest(209, coalesce((select max(substring(i.number from '^2026-(\d+)$')::int)+1 from public.invoices i where i.number ~ '^2026-\d+$'),1))),
 ('Torben Schmidt','Torben Schmidt','','','','','','','','','','','','','','Torben Schmidt','TS-',2026,1);

-- 3) Einstellungen (eine Zeile) -------------------------------------------
create table public.billing_settings (
  id int primary key default 1 check (id = 1),
  lodging_tax_rate numeric(5,2) not null default 6.25,
  lodging_tax_vat numeric(5,2) not null default 7,
  lodging_tax_since date not null default '2026-10-01',
  default_payment_days int not null default 3,
  interest_note text not null default 'Bei Zahlungsverzug berechnen wir Verzugszinsen in Höhe von 9 Prozentpunkten über dem Basiszinssatz (§ 288 Abs. 2 BGB).',
  dunning1_days int not null default 1,
  dunning2_days int not null default 7,
  dunning2_fee numeric(10,2) not null default 40,
  updated_at timestamptz not null default now()
);
insert into public.billing_settings (id) values (1);
alter table public.billing_settings enable row level security;
create policy "Einstellungen lesen" on public.billing_settings for select to authenticated using (public.is_member());
create policy "Einstellungen ändern" on public.billing_settings for update to authenticated using (public.is_editor()) with check (public.is_editor());

-- 4) Rechnungen erweitern ---------------------------------------------------
alter table public.invoices
  add column source text not null default 'import' check (source in ('import','tool')),
  add column issuer text,
  add column issuer_snapshot jsonb,
  add column customer_id uuid references public.customers(id) on delete set null,
  add column customer_snapshot jsonb,
  add column lines jsonb,
  add column lodging_tax numeric(10,2),
  add column lodging_exempt boolean not null default false,
  add column lodging_exempt_note text,
  add column notes text,
  add column paid_at date,
  add column sent_at timestamptz,
  add column dunning_level int not null default 0,
  add column dunning_at date;

-- Geschriebene Rechnungen aus dem Tool sind unveränderlich. Änderbar bleiben nur
-- Zahlungs-, Versand- und Mahnstatus, Buchungsverknüpfung, Notiz und das einmalige Ablegen des PDFs.
create function public.protect_tool_invoice() returns trigger
language plpgsql as
$$ begin
  if tg_op = 'INSERT' then
    if new.source = 'tool' and coalesce(current_setting('app.via_rpc', true),'') <> '1' then
      raise exception 'Rechnungen aus dem Tool werden nur über create_invoice angelegt';
    end if;
    return new;
  end if;
  if old.source = 'tool' then
    if (new.number, new.invoice_date, new.due_date, new.customer, new.customer_snapshot, new.issuer, new.issuer_snapshot,
        new.unit_id, new.location_text, new.period_start, new.period_end, new.quantity, new.unit_price, new.vat_rate,
        new.lines, new.net, new.vat, new.total, new.lodging_tax, new.lodging_exempt, new.is_storno, new.cancels, new.source)
       is distinct from
       (old.number, old.invoice_date, old.due_date, old.customer, old.customer_snapshot, old.issuer, old.issuer_snapshot,
        old.unit_id, old.location_text, old.period_start, old.period_end, old.quantity, old.unit_price, old.vat_rate,
        old.lines, old.net, old.vat, old.total, old.lodging_tax, old.lodging_exempt, old.is_storno, old.cancels, old.source) then
      raise exception 'Geschriebene Rechnungen können nicht geändert werden – bitte stornieren';
    end if;
    if old.file_path is not null and new.file_path is distinct from old.file_path then
      raise exception 'Das PDF einer geschriebenen Rechnung kann nicht ersetzt werden';
    end if;
  end if;
  return new;
end $$;
create trigger invoices_protect before insert or update on public.invoices
  for each row execute function public.protect_tool_invoice();

drop policy "Rechnungen löschen" on public.invoices;
create policy "Rechnungen löschen" on public.invoices
  for delete to authenticated using (public.is_editor() and public.can_see_unit(unit_id) and source <> 'tool');

drop policy "Editoren löschen Rechnungs-PDFs" on storage.objects;
create policy "Editoren löschen Rechnungs-PDFs" on storage.objects
  for delete to authenticated using (
    bucket_id = 'rechnungen' and public.is_editor()
    and not exists (select 1 from public.invoices i where i.file_path = storage.objects.name and i.source = 'tool'));

-- 5) Rechnung anlegen: Nummer wird hier vergeben (lückenlos, fortlaufend je Absender) --
create function public.create_invoice(p jsonb) returns public.invoices
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
  select * into iss from public.issuers where id = p->>'issuer' for update;
  if not found then raise exception 'Unbekannter Absender'; end if;
  if iss.number_year <> yr then
    update public.issuers set number_year = yr, next_no = 1 where id = iss.id;
    iss.number_year := yr; iss.next_no := 1;
  end if;
  n := iss.next_no;
  loop
    num := iss.number_prefix || yr || '-' || lpad(n::text, iss.number_digits, '0');
    exit when not exists (select 1 from public.invoices where number = num);
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
revoke all on function public.create_invoice(jsonb) from public, anon;
grant execute on function public.create_invoice(jsonb) to authenticated;
