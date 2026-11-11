-- Bestätigte Abreise (fest zugesagter Auszug)
alter table public.bookings add column departure_confirmed date;
alter table public.bookings add constraint bookings_dep_after_start
  check (departure_confirmed is null or departure_confirmed >= start_date);
