-- Application conflicts must be explicit HTTP 409, not retryable database serialization failures.
begin;
create or replace function public.submit_point_kick(attack_id uuid,question_id uuid,command_id uuid,
 swipe_dx double precision,swipe_dy double precision) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); a app_private.point_attacks; s public.game_spots; q app_private.attack_questions;
 prior jsonb; result jsonb; spot_key text; power double precision; vz double precision; vh double precision;
 crossing double precision; height double precision; landing_x double precision; lane integer;
 outcome text; captured boolean:=false; damage integer:=0;
begin
 if actor is null or not app_private.is_edu_player() then raise exception 'Sign in required.' using errcode='42501'; end if;
 if command_id is null then raise exception 'A command ID is required.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,7241));
 select x.spot_id into spot_key from app_private.point_attacks x where x.id=attack_id and x.user_id=actor;
 if spot_key is null then raise exception 'Attack unavailable.' using errcode='42501'; end if;
 select * into s from public.game_spots where id=spot_key for update;
 select * into a from app_private.point_attacks where id=attack_id for update;
 select r.result into prior from app_private.attack_shots r where r.attack_id=a.id and r.command_id=submit_point_kick.command_id;
 if prior is not null then return prior; end if;
 if a.status<>'active' or a.expires_at<=now() or a.capture_epoch<>s.capture_epoch or s.owner_team_id=a.team_id then
   raise exception 'This attack has ended or the point changed. Return to the map.' using errcode='PT409'; end if;
 if a.current_question_id is distinct from question_id then raise exception 'This question was already resolved. Refresh the attack.' using errcode='PT409'; end if;
 if swipe_dx is null or swipe_dy is null or not(swipe_dx between -400 and 400) or not(swipe_dy between -650 and -45) then
   raise exception 'Invalid kick.' using errcode='22023'; end if;
 select * into q from app_private.attack_questions where id=a.current_question_id;
 -- Identical to FootballShot.fromSwipe and goal aperture rules; the client never supplies an outcome, team or damage value.
 power:=greatest(.35,least(1.0,-swipe_dy/220)); vz:=18+8*power; vh:=8+2*power;
 crossing:=30/vz; height:=1+vh*crossing-9.8*crossing*crossing/2;
 landing_x:=30*greatest(-.65,least(.65,swipe_dx/(-swipe_dy)));
 if height-.18>3 and height+.18<12 then
   for i in 0..3 loop
     if abs(landing_x-(-15+i*10))+.18<4.2 then lane:=i; exit; end if;
   end loop;
 end if;
 outcome:=case when lane is null then 'miss' when q.choices->lane->>'id'=q.correct_option_id then 'correct' else 'wrong' end;
 if outcome='correct' then
   damage:=least(25,s.hp); captured:=s.hp<=25;
   update public.game_spots set hp=case when captured then max_hp else hp-25 end,
     owner_team_id=case when captured then a.team_id else owner_team_id end,
     capture_epoch=capture_epoch+case when captured then 1 else 0 end,
     revision=revision+1,updated_at=clock_timestamp() where id=s.id;
 end if;
 update app_private.point_attacks set sequence=sequence+1,
   correct_count=correct_count+case when outcome='correct' then 1 else 0 end,
   wrong_count=wrong_count+case when outcome='wrong' then 1 else 0 end,
   miss_count=miss_count+case when outcome='miss' then 1 else 0 end,
   status=case when captured then 'captured' else 'active' end,
   expires_at=clock_timestamp()+interval '15 minutes' where id=a.id;
 if not captured then
   if exists(select 1 from app_private.question_bank b where b.active and b.is_test=s.is_test) then
     perform app_private.deal_attack_question(a.id);
   else
     update app_private.point_attacks set status='bank_unavailable' where id=a.id;
   end if;
 end if;
 result:=jsonb_build_object('outcome',outcome,'lane',lane,'damage',damage,'captured',captured,'state',app_private.attack_payload(a.id));
 insert into app_private.attack_shots(attack_id,command_id,question_id,result) values(a.id,command_id,q.id,result);
 return result;
end;
$$;
revoke all on function public.submit_point_kick(uuid,uuid,uuid,double precision,double precision) from public,anon;
grant execute on function public.submit_point_kick(uuid,uuid,uuid,double precision,double precision) to authenticated;
notify pgrst,'reload schema';
commit;
