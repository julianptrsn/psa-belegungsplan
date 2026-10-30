-- Einmalig: Buchungen mit offener Abreise enden am Tag nach "Abgerechnet bis".
-- Betrifft nur Buchungen, die eine Rechnung haben, aber kein Abreisedatum.
update public.bookings
set end_original = invoiced_until + 1
where end_original is null
  and extended_until is null
  and invoiced_until is not null
  and invoiced_until >= start_date;
