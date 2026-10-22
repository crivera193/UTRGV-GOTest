-- SQL editor, verified UTRGV-GO only. All synthetic users/memberships roll back.
begin;
create function pg_temp.assert_denied(statement text) returns void language plpgsql as $$
begin
  begin
    execute statement;
  exception when insufficient_privilege or undefined_function then return;
  end;
  raise exception 'Expected permission rejection: %', statement;
end;
$$;
do $$
declare a uuid := gen_random_uuid(); b uuid := gen_random_uuid();
begin
  perform set_config('app.team_a', a::text, true);
  perform set_config('app.team_b', b::text, true);
  insert into auth.users(id,email,aud,role) values
    (a, 'team-a-' || a || '@example.edu','authenticated','authenticated'),
    (b, 'team-b-' || b || '@example.edu','authenticated','authenticated');
  if (select count(*) from public.game_teams) <> 3 then raise exception 'Canonical team count'; end if;
end $$;
set local role anon;
select pg_temp.assert_denied('select public.choose_team(''health_science'')');
select pg_temp.assert_denied('select * from public.account_teams');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('app.team_a'),true);
do $$ begin
  if (select count(*) from public.account_teams) <> 0 then raise exception 'New player must be unassigned'; end if;
  if (select count(*) from public.game_teams) <> 3 then raise exception 'Team catalog unreadable'; end if;
  begin
    perform public.choose_team('invalid');
    raise exception 'Invalid choice accepted';
  exception when invalid_parameter_value then null; end;
  begin
    perform public.choose_team(null);
    raise exception 'Null choice accepted';
  exception when invalid_parameter_value then null; end;
  if public.choose_team('health_science') <> 'health_science' then raise exception 'First selection'; end if;
  if public.choose_team('health_science') <> 'health_science' then raise exception 'Same retry'; end if;
  if public.choose_team('math_engineering') <> 'health_science' then raise exception 'Different retry overwrote team'; end if;
end $$;
select pg_temp.assert_denied('select public.choose_team(''art_stuff'', gen_random_uuid())');
select pg_temp.assert_denied('update public.account_teams set team_id=''art_stuff''');
select pg_temp.assert_denied('delete from public.account_teams');
select pg_temp.assert_denied('truncate public.account_teams');
select pg_temp.assert_denied(format('insert into public.account_teams(user_id,team_id) values (%L,''art_stuff'')',current_setting('app.team_b')));
select pg_temp.assert_denied(format('insert into public.account_teams(user_id,team_id) values (%L,''art_stuff'') on conflict(user_id) do update set team_id=excluded.team_id',current_setting('app.team_a')));
select pg_temp.assert_denied('delete from public.player_profiles');
select pg_temp.assert_denied('update public.game_teams set id=''other''');
select set_config('request.jwt.claim.sub',current_setting('app.team_b'),true);
do $$ begin
  if (select count(*) from public.account_teams) <> 0 then raise exception 'Cross-account read leaked'; end if;
  if public.choose_team('art_stuff') <> 'art_stuff' then raise exception 'Second account'; end if;
  if (select count(*) from public.account_teams) <> 1 then raise exception 'Own row not readable'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('app.team_a'),true);
do $$ begin
  if (select team_id from public.account_teams) <> 'health_science' then raise exception 'Restored account lost membership'; end if;
end $$;
reset role;
-- Even an accidental future broad grant cannot bypass the immutable trigger.
select pg_temp.assert_denied(format('update public.account_teams set team_id=''art_stuff'' where user_id=%L',current_setting('app.team_a')));
select pg_temp.assert_denied(format('delete from public.account_teams where user_id=%L',current_setting('app.team_a')));
-- Profile deletion/recreation cannot touch an account-keyed assignment.
delete from public.player_profiles where id=current_setting('app.team_a')::uuid;
insert into public.player_profiles(id) values(current_setting('app.team_a')::uuid);
do $$ begin
  if (select team_id from public.account_teams where user_id=current_setting('app.team_a')::uuid) <> 'health_science' then raise exception 'Profile recreation reset membership'; end if;
end $$;
rollback;
select 'PASS: canonical teams, anonymous/invalid/forged calls, own-row RLS, immutable update/delete/upsert, retries, account isolation and profile recreation; all synthetic data rolled back' as result;
