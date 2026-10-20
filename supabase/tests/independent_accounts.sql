-- Run in the new project SQL editor. Synthetic records are rolled back.
begin;
do $$
declare a uuid := gen_random_uuid(); b uuid := gen_random_uuid(); rejected boolean := false;
begin
  perform set_config('app.audit_a', a::text, true);
  perform set_config('app.audit_b', b::text, true);
  insert into auth.users(id, email, aud, role) values
    (a, 'audit-a-' || a::text || '@example.edu', 'authenticated', 'authenticated'),
    (b, 'audit-b-' || b::text || '@example.edu', 'authenticated', 'authenticated');
  if (select count(*) from public.player_profiles where id in (a,b)) <> 2 then
    raise exception 'Profile creation failed';
  end if;
  begin
    insert into auth.users(id,email) values(gen_random_uuid(),'audit@example.com');
  exception when raise_exception then
    if SQLERRM <> 'A valid .edu email address is required.' then raise; end if;
    rejected := true;
  end;
  if not rejected then raise exception 'Non-edu signup was not rejected'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('app.audit_a'),true);
do $$ begin
  if not app_private.is_edu_player() then raise exception 'Edu eligibility failed'; end if;
  if (select count(*) from public.player_profiles) <> 1 then raise exception 'Profile isolation failed for player A'; end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('app.audit_b'),true);
do $$ begin
  if (select count(*) from public.player_profiles) <> 1 then raise exception 'Profile isolation failed for player B'; end if;
end $$;
reset role;
rollback;
select 'PASS: .edu accepted, non-.edu rejected, profiles created, account isolation enforced; synthetic rows rolled back' as result;
