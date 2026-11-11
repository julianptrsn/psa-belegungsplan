-- Einmalig: Beendete Buchungen, deren letzte Rechnung vor dem geplanten Ende aufhört,
-- bekommen als bestätigten Auszug den letzten abgerechneten Tag ("abgerechnet bis").
-- Hintergrund: Die Gäste sind früher ausgezogen als geplant (z. B. ProStaff am 08.08.25),
-- im Tool stand aber noch das ursprüngliche Ende -> die Tage tauchten unter "Abrechnung fällig" auf.
--
-- Nur Buchungen, deren geplantes Ende mehr als 30 Tage zurückliegt – bei frisch beendeten
-- Aufenthalten kann die Schlussrechnung ja noch fehlen.
-- Buchungen ganz ohne Rechnung werden NICHT angefasst.

-- 1) Vorschau: Diese Buchungen würden geändert
select company, unit_id, start_date,
       coalesce(extended_until, end_original) as geplantes_ende,
       invoiced_until as abgerechnet_bis
from public.bookings
where departure_confirmed is null
  and invoiced_until is not null
  and invoiced_until >= start_date
  and coalesce(extended_until, end_original) > invoiced_until
  and coalesce(extended_until, end_original) < current_date - 30
order by company;

-- 2) Ändern (nach Prüfung der Vorschau ausführen)
update public.bookings
set departure_confirmed = invoiced_until
where departure_confirmed is null
  and invoiced_until is not null
  and invoiced_until >= start_date
  and coalesce(extended_until, end_original) > invoiced_until
  and coalesce(extended_until, end_original) < current_date - 30;
