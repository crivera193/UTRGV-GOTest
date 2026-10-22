-- Verified target: oipidltfvzodpiumdsaq / UTRGV-GO only.
-- Additive; deliberately fails if an unexpected legacy team table exists.
begin;
create table public.game_teams (
  id text primary key check (id in ('health_science','math_engineering','art_stuff')),
  display_name text not null,
  color_name text not null,
  description text not null
);
insert into public.game_teams values
 ('health_science','Health and Science','blue','Stay curious. Explore life, wellbeing and the world around you.'),
 ('math_engineering','Math and Engineering','red','Think boldly. Find patterns, solve puzzles and build new possibilities.'),
 ('art_stuff','Art and Stuff','yellow','Make your mark. Bring imagination, expression and a fresh perspective.');

create table public.account_teams (
  user_id uuid primary key references auth.users(id) on delete restrict,
  team_id text not null references public.game_teams(id) on delete restrict,
  chosen_at timestamptz not null default now()
);
comment on table public.account_teams is
 'Permanent account membership, independent of editable profiles. No ordinary client writes; choose_team is the sole assignment API.';
alter table public.game_teams enable row level security;
alter table public.account_teams enable row level security;
revoke all on public.game_teams, public.account_teams from public, anon, authenticated;
grant select on public.game_teams, public.account_teams to authenticated;
create policy edu_players_read_teams on public.game_teams for select to authenticated
 using ((select app_private.is_edu_player()));
create policy player_reads_own_team on public.account_teams for select to authenticated
 using (user_id = (select auth.uid()) and (select app_private.is_edu_player()));

create function app_private.prevent_team_mutation()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'Account team membership is permanent.' using errcode = '42501';
end;
$$;
revoke all on function app_private.prevent_team_mutation() from public, anon, authenticated;
create trigger account_team_is_permanent before update or delete on public.account_teams
 for each row execute function app_private.prevent_team_mutation();

create function public.choose_team(requested_team text)
returns text language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := auth.uid();
  saved_team text;
begin
  if actor is null or not app_private.is_edu_player() then
    raise exception 'An authenticated .edu account is required.' using errcode = '42501';
  end if;
  if requested_team is null or requested_team not in ('health_science','math_engineering','art_stuff') then
    raise exception 'Unknown team.' using errcode = '22023';
  end if;
  -- The primary key arbitrates concurrent requests. Never use DO UPDATE.
  insert into public.account_teams(user_id, team_id) values (actor, requested_team)
    on conflict (user_id) do nothing;
  -- A new statement snapshot sees the winning committed row after a conflict wait.
  select a.team_id into saved_team from public.account_teams a where a.user_id = actor;
  if saved_team is null then
    raise exception 'Membership could not be confirmed; retry.' using errcode = '40001';
  end if;
  return saved_team;
end;
$$;
revoke all on function public.choose_team(text) from public, anon, authenticated;
grant execute on function public.choose_team(text) to authenticated;
notify pgrst, 'reload schema';
commit;
