-- Admin-only isolated boundary verification. All edits are rolled back.
begin;
do $$
declare actor uuid; aid uuid; fresh jsonb;
begin
 select id into actor from auth.users where email='team-e2e-a-r1792678030@example.edu'
 and raw_app_meta_data @> '{"live_game_test":true}'::jsonb;
 select a.id into aid from app_private.point_attacks a join public.game_spots s on s.id=a.spot_id
 where a.user_id=actor and s.id='qa-timed-boundary-20261022' and s.is_test and a.status='completed'
 order by a.created_at desc limit 1;
 if actor is null or aid is null then raise exception 'Complete the isolated REST fixture first'; end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 update app_private.point_attacks set created_at=clock_timestamp()-interval '9 minutes 59 seconds' where id=aid;
 begin
  perform public.begin_point_attack('qa-timed-boundary-20261022',gen_random_uuid(),0,0,0,clock_timestamp()-interval '1 millisecond');
  raise exception 'Accepted before ten minutes';
 exception when sqlstate 'PT429' then null;
 end;
 update app_private.point_attacks set created_at=clock_timestamp()-interval '10 minutes 1 second' where id=aid;
 fresh:=public.begin_point_attack('qa-timed-boundary-20261022',gen_random_uuid(),0,0,0,clock_timestamp()-interval '1 millisecond');
 if fresh->>'status'<>'active' or (fresh->>'sequence')::int<>0 or fresh->>'id'=aid::text then raise exception 'Did not open after ten minutes'; end if;
end;
$$;
rollback;
select 'PASS: blocked at 9:59; allowed at 10:01; all fixture changes rolled back' as result;
