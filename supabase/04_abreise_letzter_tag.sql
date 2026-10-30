-- Abreise = letzter belegter Tag (einschließlich), z. B. 01.11.–30.11. = 30 Nächte.

-- 1) Regel lockern: Abreise darf auch am Anreisetag liegen (1 Nacht)
alter table public.bookings drop constraint if exists bookings_check;
alter table public.bookings drop constraint if exists bookings_check1;
alter table public.bookings add constraint bookings_end_after_start
  check (end_original is null or end_original >= start_date);
alter table public.bookings add constraint bookings_ext_after_start
  check (extended_until is null or extended_until >= start_date);

-- 2) Vom Rechnungsimport gesetzte Abreisen (Tag nach "Abgerechnet bis") um einen Tag zurücksetzen
update public.bookings set end_original = invoiced_until
  where invoiced_until is not null and end_original = invoiced_until + 1;
update public.bookings set extended_until = invoiced_until
  where invoiced_until is not null and extended_until = invoiced_until + 1;

-- 3) Buchungen mit offener Abreise auf den letzten abgerechneten Tag setzen
update public.bookings set end_original = invoiced_until
  where end_original is null and extended_until is null
    and invoiced_until is not null and invoiced_until >= start_date;
