-- NEW independent Supabase project only. Never apply to the former team's project.
begin;
create schema if not exists app_private;
revoke all on schema app_private from public, anon, authenticated;

-- Database-side rejection also covers clients bypassing Flutter validation.
create function app_private.require_edu_email()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.email is null or new.email !~* '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+edu$' then
    raise exception 'A valid .edu email address is required.';
  end if;
  return new;
end;
$$;
revoke all on function app_private.require_edu_email() from public, anon, authenticated;
create trigger independent_accounts_require_edu
before insert or update of email on auth.users
for each row execute function app_private.require_edu_email();

create table public.player_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.player_profiles enable row level security;
revoke all on public.player_profiles from anon, authenticated;
grant select on public.player_profiles to authenticated;

create function app_private.create_player_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.player_profiles(id) values (new.id);
  return new;
end;
$$;
revoke all on function app_private.create_player_profile() from public, anon, authenticated;
create trigger independent_accounts_create_profile
after insert on auth.users for each row execute function app_private.create_player_profile();

-- Read the actual Auth row, not user-editable profile metadata/JWT email claims.
create function app_private.is_edu_player()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.users u
    where u.id = auth.uid()
      and u.email ~* '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+edu$'
  );
$$;
revoke all on function app_private.is_edu_player() from public, anon;
grant usage on schema app_private to authenticated;
grant execute on function app_private.is_edu_player() to authenticated;
create policy player_reads_own_profile on public.player_profiles
for select to authenticated
using (id = (select auth.uid()) and (select app_private.is_edu_player()));
commit;
