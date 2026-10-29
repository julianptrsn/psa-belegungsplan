-- Grundstruktur: Mitglieder, Buchungen, Zugriffsregeln (bereits ausgeführt am 29.10.2026)

create table public.members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  name text,
  can_edit boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  unit_id text not null,
  company text not null,
  contact text default '',
  persons int not null check (persons > 0),
  start_date date not null,
  end_original date,
  extended_until date,
  price numeric(10,2),
  price_model text not null default 'pp_night'
    check (price_model in ('pp_night','unit_night','pp_month','unit_month')),
  invoiced_until date,
  state text not null default 'confirmed' check (state in ('confirmed','reserved')),
  notes text default '',
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid(),
  updated_at timestamptz not null default now(),
  updated_by uuid default auth.uid(),
  check (end_original is null or end_original > start_date),
  check (extended_until is null or extended_until > start_date)
);

create function public.is_member() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from members where user_id = auth.uid()) $$;

create function public.is_editor() returns boolean
language sql stable security definer set search_path = public as
$$ select exists (select 1 from members where user_id = auth.uid() and can_edit) $$;

alter table public.members enable row level security;
alter table public.bookings enable row level security;

create policy "Mitglieder sehen Mitglieder" on public.members
  for select to authenticated using (public.is_member());

create policy "Mitglieder lesen Buchungen" on public.bookings
  for select to authenticated using (public.is_member());
create policy "Editoren legen an" on public.bookings
  for insert to authenticated with check (public.is_editor());
create policy "Editoren ändern" on public.bookings
  for update to authenticated using (public.is_editor()) with check (public.is_editor());
create policy "Editoren löschen" on public.bookings
  for delete to authenticated using (public.is_editor());

create function public.touch_booking() returns trigger
language plpgsql as
$$ begin new.updated_at = now(); new.updated_by = auth.uid(); return new; end $$;
create trigger bookings_touch before update on public.bookings
  for each row execute function public.touch_booking();

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as
$$ begin
  insert into members (user_id, name) values (new.id, split_part(new.email, '@', 1));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

alter publication supabase_realtime add table public.bookings;
