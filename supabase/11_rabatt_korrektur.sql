-- Einmalige Korrektur für bereits importierte Zervant-Rechnungen mit Rabatt (z. B. Sandbergweg, 50 %):
-- Der Importer hatte den Listenpreis übernommen. Einzelpreis und Positionen werden auf den tatsächlich
-- berechneten Nettobetrag umgerechnet. Das Ergebnis listet alle korrigierten Rechnungen mit ihrer Buchung auf.
-- Einmal im Supabase SQL Editor ausführen.

with r as (
  select i.id, i.net,
         coalesce((select sum((e->>'q')::numeric * (e->>'u')::numeric)
                   from jsonb_array_elements(case when jsonb_typeof(i.positions) = 'array' then i.positions else '[]'::jsonb end) e
                   where e->>'q' is not null and e->>'u' is not null),
                  i.quantity * i.unit_price) as list
  from public.invoices i
  where i.source = 'import' and not i.is_storno and i.net is not null and i.net > 0
)
, u as (
update public.invoices i set
  unit_price = case when i.unit_price is not null then round(i.unit_price * r.net / r.list, 2) end,
  positions = case when jsonb_typeof(i.positions) = 'array' then
    (select jsonb_agg(case when e->>'u' is not null
                           then jsonb_set(e, '{u}', to_jsonb(round((e->>'u')::numeric * r.net / r.list, 2)))
                           else e end)
     from jsonb_array_elements(i.positions) e)
    else i.positions end
from r
where r.id = i.id and r.list is not null and r.list > r.net + 0.5
returning i.id, i.number, i.booking_id, i.period_start, i.period_end, i.unit_price, round(100 - 100 * r.net / r.list, 1) as rabatt_prozent
)
-- Ergebnis: alle korrigierten Rechnungen mit der zugehörigen Buchung – Buchungspreis bitte im Tool prüfen
select u.number as rechnung, u.rabatt_prozent, u.period_start as von, u.period_end as bis, u.unit_price as preis_berechnet,
       b.company as firma, b.unit_id as wohnung, b.price as preis_in_buchung, b.price_model as preismodell
from u left join public.bookings b on b.id = u.booking_id
order by b.unit_id, u.period_start;
