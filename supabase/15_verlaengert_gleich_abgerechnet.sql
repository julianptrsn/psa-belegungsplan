-- „Verlängert bis“ = „abgerechnet bis“ (Datum der letzten Rechnung).
-- Liegt die letzte Rechnung nach der ursprünglichen Abreise, ist das die Verlängerung.
-- Sonst gibt es keine Verlängerung (extended_until = null).
-- Das Tool rechnet ab jetzt selbst so; dieses Skript gleicht die gespeicherten Daten an.

-- 1) Vorschau: Diese Buchungen ändern sich
select company, unit_id, start_date, end_original,
       extended_until as verlaengert_bisher,
       case when end_original is not null and invoiced_until > end_original
            then invoiced_until end as verlaengert_neu,
       invoiced_until as abgerechnet_bis
from public.bookings
where extended_until is distinct from
      case when end_original is not null and invoiced_until > end_original
           then invoiced_until end
order by company;

-- 2) Ändern (nach Prüfung der Vorschau ausführen)
update public.bookings
set extended_until = case when end_original is not null and invoiced_until > end_original
                          then invoiced_until end
where extended_until is distinct from
      case when end_original is not null and invoiced_until > end_original
           then invoiced_until end;
