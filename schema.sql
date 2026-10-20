-- ProofOfWork schema for Supabase. Run once in Dashboard > SQL Editor.
-- Public evidence labels are descriptive only; this app does not verify links or claims.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  slug text not null unique,
  full_name text not null default 'New creator' check (char_length(full_name) <= 80),
  bio text not null default '' check (char_length(bio) <= 500),
  skills text[] not null default '{}',
  is_public boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_slug_format check (slug ~ '^[a-z0-9][a-z0-9-]{2,39}$')
);

create table if not exists public.portfolio_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 120),
  description text not null default '' check (char_length(description) <= 1200),
  evidence_url text check (evidence_url is null or evidence_url ~* '^https?://'),
  entry_type text not null default 'project' check (entry_type in ('project','certificate','hackathon')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists portfolio_entries_user_created_idx on public.portfolio_entries(user_id, created_at desc);

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin new.updated_at = now(); return new; end; $$;
drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles for each row execute function public.set_updated_at();
drop trigger if exists portfolio_entries_set_updated_at on public.portfolio_entries;
create trigger portfolio_entries_set_updated_at before update on public.portfolio_entries for each row execute function public.set_updated_at();

-- Create a profile automatically for every new Auth user. The slug is based on
-- the requested username/email prefix plus a short UUID suffix to avoid collisions.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare base_slug text; chosen_slug text;
begin
  base_slug := lower(regexp_replace(coalesce(new.raw_user_meta_data ->> 'slug', split_part(coalesce(new.email, 'creator'), '@', 1)), '[^a-z0-9]+', '-', 'g'));
  base_slug := trim(both '-' from base_slug);
  if char_length(base_slug) < 3 then base_slug := 'creator'; end if;
  base_slug := left(base_slug, 28);
  chosen_slug := base_slug || '-' || substr(replace(new.id::text, '-', ''), 1, 8);
  insert into public.profiles (id, slug, full_name, bio, skills)
  values (new.id, chosen_slug, coalesce(nullif(new.raw_user_meta_data ->> 'full_name',''), 'New creator'), '', '{}')
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.portfolio_entries enable row level security;
revoke all on public.profiles from anon, authenticated;
revoke all on public.portfolio_entries from anon, authenticated;
grant select on public.profiles to anon, authenticated;
grant insert, update, delete on public.profiles to authenticated;
grant select on public.portfolio_entries to anon, authenticated;
grant insert, update, delete on public.portfolio_entries to authenticated;

-- Only public profiles are readable without sign-in. Owners can always see their own profile.
drop policy if exists "Public profiles are viewable" on public.profiles;
create policy "Public profiles are viewable" on public.profiles for select to anon, authenticated using (is_public or (select auth.uid()) = id);
drop policy if exists "Users insert own profile" on public.profiles;
create policy "Users insert own profile" on public.profiles for insert to authenticated with check ((select auth.uid()) = id);
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using ((select auth.uid()) = id) with check ((select auth.uid()) = id);
drop policy if exists "Owners manage own entries" on public.portfolio_entries;
create policy "Owners manage own entries" on public.portfolio_entries for all to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "Entries on public profiles are readable" on public.portfolio_entries;
create policy "Entries on public profiles are readable" on public.portfolio_entries for select to anon, authenticated using (exists (select 1 from public.profiles p where p.id = portfolio_entries.user_id and p.is_public));
