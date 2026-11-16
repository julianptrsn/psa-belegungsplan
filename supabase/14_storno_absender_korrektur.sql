-- Korrektur: Importierte Stornorechnungen, die der falschen Originalrechnung zugeordnet wurden.
-- Hintergrund: Rechnungsnummern gibt es bei PSA und bei Torben doppelt (z. B. 2026-98).
-- Ein Storno wurde dabei der gleichnamigen Rechnung des anderen Absenders zugeordnet
-- und landete so bei der falschen Wohnung bzw. beim falschen Absender.
-- Erkennung: Es gibt beim ANDEREN Absender eine Originalrechnung mit dieser Nummer und demselben Kunden,
-- beim aktuellen Absender aber nicht.

-- 1) Vorschau: Diese Stornos werden umgehängt
select s.number            as storno,
       s.cancels           as storniert_rechnung,
       s.customer          as kunde,
       s.total             as betrag,
       s.issuer            as absender_bisher,
       s.unit_id           as wohnung_bisher,
       o.issuer            as absender_neu,
       o.unit_id           as wohnung_neu,
       b.company           as buchung_bisher,
       b.invoiced_until    as buchung_bisher_abgerechnet_bis
from public.invoices s
join public.invoices o
  on o.number = s.cancels and not o.is_storno
 and o.issuer is distinct from s.issuer
 and lower(regexp_replace(coalesce(o.customer,''), '[^[:alnum:]]', '', 'g')) = lower(regexp_replace(coalesce(s.customer,''), '[^[:alnum:]]', '', 'g'))
left join public.bookings b on b.id = s.booking_id
where s.is_storno and s.source = 'import'
  and not exists (
    select 1 from public.invoices o2
    where o2.number = s.cancels and not o2.is_storno
      and o2.issuer is not distinct from s.issuer
      and lower(regexp_replace(coalesce(o2.customer,''), '[^[:alnum:]]', '', 'g')) = lower(regexp_replace(coalesce(s.customer,''), '[^[:alnum:]]', '', 'g')))
  and not exists (select 1 from public.invoices x where x.issuer = o.issuer and x.number = s.number);

-- 2) Korrektur ausführen (Wohnung, Buchung und Absender der richtigen Originalrechnung übernehmen)
update public.invoices s
set unit_id = o.unit_id,
    booking_id = o.booking_id,
    issuer = o.issuer
from public.invoices o
where o.number = s.cancels and not o.is_storno
  and o.issuer is distinct from s.issuer
  and lower(regexp_replace(coalesce(o.customer,''), '[^[:alnum:]]', '', 'g')) = lower(regexp_replace(coalesce(s.customer,''), '[^[:alnum:]]', '', 'g'))
  and s.is_storno and s.source = 'import'
  and not exists (
    select 1 from public.invoices o2
    where o2.number = s.cancels and not o2.is_storno
      and o2.issuer is not distinct from s.issuer
      and lower(regexp_replace(coalesce(o2.customer,''), '[^[:alnum:]]', '', 'g')) = lower(regexp_replace(coalesce(s.customer,''), '[^[:alnum:]]', '', 'g')))
  and not exists (select 1 from public.invoices x where x.issuer = o.issuer and x.number = s.number)
returning s.number, s.customer, s.issuer, s.unit_id;
