-- КиноЧат: схема базы. Выполнить один раз в Supabase → SQL Editor.

create table if not exists public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-Z0-9]{6}$'),
  name text not null check (char_length(name) between 1 and 60),
  playback jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key,
  room_id uuid not null references public.rooms (id) on delete cascade,
  user_id text not null check (char_length(user_id) <= 64),
  user_name text not null check (char_length(user_name) between 1 and 40),
  body text not null check (char_length(body) between 1 and 1000),
  system boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists messages_room_created
  on public.messages (room_id, created_at desc);

-- Вход без регистрации: приложение работает под ролью anon.
-- Комнату открывает тот, кто знает её код.
alter table public.rooms enable row level security;
alter table public.messages enable row level security;

drop policy if exists rooms_read on public.rooms;
drop policy if exists rooms_create on public.rooms;
drop policy if exists rooms_update on public.rooms;
drop policy if exists messages_read on public.messages;
drop policy if exists messages_create on public.messages;

create policy rooms_read on public.rooms for select to anon using (true);
create policy rooms_create on public.rooms for insert to anon with check (true);
create policy rooms_update on public.rooms for update to anon using (true) with check (true);
create policy messages_read on public.messages for select to anon using (true);
create policy messages_create on public.messages for insert to anon with check (true);

-- Менять в комнате можно только состояние плеера.
revoke update on public.rooms from anon;
grant update (playback) on public.rooms to anon;

-- Часы сервера: по ним устройства сверяют позицию видео.
create or replace function public.server_time()
returns timestamptz
language sql
stable
as $$ select now() $$;

grant execute on function public.server_time() to anon;
