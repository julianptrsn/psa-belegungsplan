-- Einmalig: Buchungen mit offener Abreise enden am letzten abgerechneten Tag.
-- (Abreise = letzter Tag einschließlich, wie auf den Rechnungen.)
update public.bookings
set end_original = invoiced_until
where end_original is null
  and extended_until is null
  and invoiced_until is not null
  and invoiced_until >= start_date;
