-- Four timed questions, at most 25% damage, one attempt per player/point per ten minutes.
begin;
alter table public.game_spots alter column hp type numeric(12,4) using hp::numeric;
alter table app_private.point_attacks drop constraint point_attacks_status_check;
alter table app_private.point_attacks add constraint point_attacks_status_check
 check(status in ('active','captured','completed','superseded','expired','bank_unavailable'));
alter table app_private.point_attacks add column timeout_count integer not null default 0,
 add column damage_dealt numeric(12,4) not null default 0,
 add column last_outcome text;
alter table app_private.attack_questions add column due_at timestamptz not null default clock_timestamp()+interval '15 seconds',
 add column resolved_at timestamptz,
 add column outcome text check(outcome in ('correct','wrong','miss','timeout'));
-- Retire unlimited legacy attempts; preserve all already-earned damage and history.
update app_private.point_attacks set status='expired' where status='active';
create index point_attack_cooldown_lookup on app_private.point_attacks(user_id,spot_id,created_at desc);

create or replace function app_private.attack_payload(aid uuid) returns jsonb
language sql volatile security definer set search_path='' as $$
 select jsonb_build_object('id',a.id,'spot_id',a.spot_id,'team_id',a.team_id,'status',a.status,
 'sequence',a.sequence,'questions_total',4,'correct_count',a.correct_count,'wrong_count',a.wrong_count,
 'miss_count',a.miss_count,'timeout_count',a.timeout_count,'damage_dealt',a.damage_dealt,'last_outcome',a.last_outcome,
 'expires_at',a.expires_at,'server_now',clock_timestamp(),'cooldown_until',a.created_at+interval '10 minutes',
 'point',to_jsonb(s)-'is_test',
 'question',jsonb_build_object('instance_id',q.id,'bank_id',q.bank_id,'version',q.bank_version,
 'prompt',q.prompt,'choices',q.choices,'due_at',q.due_at))
 from app_private.point_attacks a join public.game_spots s on s.id=a.spot_id
 left join app_private.attack_questions q on q.id=a.current_question_id where a.id=aid;
$$;
revoke all on function app_private.attack_payload(uuid) from public,anon,authenticated;
create or replace function app_private.deal_attack_question(aid uuid) returns void
language plpgsql security definer set search_path='' as $$
declare bank app_private.question_bank; prev text; chosen uuid; shuffled jsonb; test_spot boolean;
begin
 select q.bank_id into prev from app_private.point_attacks a
 left join app_private.attack_questions q on q.id=a.current_question_id where a.id=aid;
 if prev is null then
   select q.bank_id into prev from app_private.attack_questions q join app_private.point_attacks a on a.id=q.attack_id
   where a.user_id=(select user_id from app_private.point_attacks where id=aid)
   order by q.created_at desc,q.id desc limit 1;
 end if;
 select s.is_test into test_spot from public.game_spots s join app_private.point_attacks a on a.spot_id=s.id where a.id=aid;
 select * into bank from app_private.question_bank b where b.active and b.is_test=test_spot
 order by exists(select 1 from app_private.attack_questions used where used.attack_id=aid and used.bank_id=b.id),
 (b.id=prev) asc nulls first,random() limit 1;
 if bank.id is null then raise exception 'No active questions are available. Please try later.' using errcode='P0001'; end if;
 select jsonb_agg(jsonb_build_object('id',(i-1)::text,'text',bank.choices[i]) order by random())
 into shuffled from generate_series(1,4) i;
 insert into app_private.attack_questions(attack_id,bank_id,bank_version,prompt,choices,correct_option_id)
 values(aid,bank.id,bank.version,bank.prompt,shuffled,bank.correct_index::text) returning id into chosen;
 update app_private.point_attacks set current_question_id=chosen where id=aid;
end;
$$;
revoke all on function app_private.deal_attack_question(uuid) from public,anon,authenticated;


-- Caller holds the actor advisory lock and spot row lock, always in that order.
-- Catch up against absolute deadlines; backgrounding/closing never pauses a question.
create function app_private.advance_timed_attack(aid uuid) returns void
language plpgsql security definer set search_path='' as $$
declare a app_private.point_attacks; s public.game_spots; q app_private.attack_questions; deadline timestamptz;
begin
 select * into a from app_private.point_attacks where id=aid for update;
 if a.status<>'active' then return; end if;
 select * into s from public.game_spots where id=a.spot_id;
 if not s.enabled or a.capture_epoch<>s.capture_epoch or s.owner_team_id=a.team_id then
   update app_private.point_attacks set status='superseded' where id=aid; return;
 end if;
 loop
   select * into a from app_private.point_attacks where id=aid;
   if a.sequence>=4 then update app_private.point_attacks set status='completed' where id=aid; return; end if;
   select * into q from app_private.attack_questions where id=a.current_question_id;
   if q.due_at>clock_timestamp() then return; end if;
   deadline:=q.due_at;
   update app_private.attack_questions set resolved_at=deadline,outcome='timeout' where id=q.id;
   update app_private.point_attacks set sequence=sequence+1,timeout_count=timeout_count+1,last_outcome='timeout',
     status=case when sequence+1>=4 then 'completed' else 'active' end where id=aid returning * into a;
   if a.status<>'active' then return; end if;
   if not exists(select 1 from app_private.question_bank b where b.active and b.is_test=s.is_test) then
     update app_private.point_attacks set status='bank_unavailable' where id=aid; return;
   end if;
   perform app_private.deal_attack_question(aid);
   update app_private.attack_questions set due_at=deadline+interval '15 seconds' where id=(select current_question_id from app_private.point_attacks where id=aid);
 end loop;
end;
$$;
revoke all on function app_private.advance_timed_attack(uuid) from public,anon,authenticated;
create or replace function public.begin_point_attack(spot_id text,request_id uuid,latitude double precision,longitude double precision,
 accuracy_meters double precision,fix_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); team text; spot public.game_spots; a app_private.point_attacks; distance_m double precision; latest_start timestamptz;
begin
 if actor is null or not app_private.is_edu_player() then raise exception 'Sign in with a .edu account.' using errcode='42501'; end if;
 select t.team_id into team from public.account_teams t where t.user_id=actor;
 if team is null then raise exception 'Choose your permanent team first.' using errcode='42501'; end if;
 if request_id is null then raise exception 'A request ID is required.' using errcode='22023'; end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,7241));
 select * into spot from public.game_spots s where s.id=spot_id for update;
 if spot.id is null or not spot.enabled or (spot.is_test and not app_private.live_test_player()) then
   raise exception 'Point unavailable.' using errcode='42501'; end if;
 select * into a from app_private.point_attacks x where x.user_id=actor and x.request_id=begin_point_attack.request_id;
 if a.id is not null then
   if a.spot_id<>spot.id then raise exception 'Request ID already belongs to another point.' using errcode='22023'; end if;
   perform app_private.advance_timed_attack(a.id);
   return app_private.attack_payload(a.id);
 end if;
 if latitude is null or longitude is null or accuracy_meters is null or fix_at is null
 or not(latitude between -90 and 90) or not(longitude between -180 and 180)
 or not(accuracy_meters between 0 and 15) or fix_at>clock_timestamp() or fix_at<clock_timestamp()-interval '10 seconds' then
   raise exception 'A fresh GPS fix with accuracy of 15 m or better is required.' using errcode='22023'; end if;
 distance_m:=6371000*2*asin(sqrt(least(1.0,power(sin(radians(latitude-spot.latitude)/2),2)
   +cos(radians(latitude))*cos(radians(spot.latitude))*power(sin(radians(longitude-spot.longitude)/2),2))));
 if distance_m+accuracy_meters>spot.attack_meters then raise exception 'Move within the point attack radius, including GPS uncertainty.' using errcode='42501'; end if;
 if spot.owner_team_id=team then raise exception 'Your team already controls this point.' using errcode='42501'; end if;
 select * into a from app_private.point_attacks x where x.user_id=actor and x.spot_id=spot.id and x.status='active' for update;
 if a.id is not null then
   perform app_private.advance_timed_attack(a.id);
   select * into a from app_private.point_attacks where id=a.id;
   if a.status='active' then return app_private.attack_payload(a.id); end if;
 end if;
 select max(x.created_at) into latest_start from app_private.point_attacks x where x.user_id=actor and x.spot_id=spot.id;
 if latest_start+interval '10 minutes'>clock_timestamp() then
   raise exception 'This point is cooling down. You may attack each point once every 10 minutes.'
   using errcode='PT429',detail=(latest_start+interval '10 minutes')::text;
 end if;
 insert into app_private.point_attacks(user_id,spot_id,team_id,request_id,capture_epoch,expires_at)
 values(actor,spot.id,team,request_id,spot.capture_epoch,clock_timestamp()+interval '60 seconds') returning * into a;
 perform app_private.deal_attack_question(a.id);
 return app_private.attack_payload(a.id);
end;
$$;
revoke all on function public.begin_point_attack(text,uuid,double precision,double precision,double precision,timestamptz) from public,anon;
grant execute on function public.begin_point_attack(text,uuid,double precision,double precision,double precision,timestamptz) to authenticated;

create or replace function public.read_point_attack(attack_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a app_private.point_attacks; s public.game_spots; spot_key text;
begin
 if auth.uid() is null or not app_private.is_edu_player() then raise exception 'Sign in required.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,7241));
 select spot_id into spot_key from app_private.point_attacks where id=attack_id and user_id=auth.uid();
 select * into s from public.game_spots where id=spot_key for update;
 select * into a from app_private.point_attacks where id=attack_id and user_id=auth.uid() for update;
 if a.id is null then raise exception 'Attack unavailable.' using errcode='42501'; end if;
 perform app_private.advance_timed_attack(a.id);
 return app_private.attack_payload(a.id);
end;
$$;
revoke all on function public.read_point_attack(uuid) from public,anon;
grant execute on function public.read_point_attack(uuid) to authenticated;


create function public.point_attack_access(spot_id text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a app_private.point_attacks; s public.game_spots;
begin
 if auth.uid() is null or not app_private.is_edu_player() then raise exception 'Sign in required.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,7241));
 select * into s from public.game_spots where id=spot_id for update;
 if s.id is null or not s.enabled or (s.is_test and not app_private.live_test_player()) then raise exception 'Point unavailable.' using errcode='42501'; end if;
 select * into a from app_private.point_attacks x where x.user_id=auth.uid() and x.spot_id=s.id order by x.created_at desc,x.id desc limit 1;
 if a.id is not null then
   perform app_private.advance_timed_attack(a.id);
   select * into a from app_private.point_attacks where id=a.id;
 end if;
 return jsonb_build_object('server_now',clock_timestamp(),'cooldown_until',a.created_at+interval '10 minutes','can_resume',coalesce(a.status='active',false));
end;
$$;
revoke all on function public.point_attack_access(text) from public,anon;
grant execute on function public.point_attack_access(text) to authenticated;
create or replace function public.submit_point_kick(attack_id uuid,question_id uuid,command_id uuid,
 swipe_dx double precision,swipe_dy double precision) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); a app_private.point_attacks; s public.game_spots; q app_private.attack_questions;
 prior jsonb; result jsonb; spot_key text; power double precision; vz double precision; vh double precision;
 crossing double precision; height double precision; landing_x double precision; lane integer;
 kick_outcome text; captured boolean:=false; damage numeric(12,4):=0;
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
 if a.status<>'active' or not s.enabled or a.capture_epoch<>s.capture_epoch or s.owner_team_id=a.team_id then
   raise exception 'This attack has ended or the point changed. Return to the map.' using errcode='PT409'; end if;
 if a.current_question_id is distinct from question_id then raise exception 'This question was already resolved. Refresh the attack.' using errcode='PT409'; end if;
 if swipe_dx is null or swipe_dy is null or not(swipe_dx between -400 and 400) or not(swipe_dy between -650 and -45) then
   raise exception 'Invalid kick.' using errcode='22023'; end if;
 perform app_private.advance_timed_attack(a.id);
 select * into a from app_private.point_attacks where id=a.id;
 if a.current_question_id is distinct from question_id or a.status<>'active' then
   return jsonb_build_object('outcome','timeout','lane',null,'damage',0,'captured',false,'state',app_private.attack_payload(a.id));
 end if;
 select * into q from app_private.attack_questions where id=a.current_question_id;
 -- Identical to FootballShot.fromSwipe and goal aperture rules; the client never supplies an kick_outcome, team or damage value.
 power:=greatest(.35,least(1.0,-swipe_dy/220)); vz:=18+8*power; vh:=8+2*power;
 crossing:=30/vz; height:=1+vh*crossing-9.8*crossing*crossing/2;
 landing_x:=30*greatest(-.65,least(.65,swipe_dx/(-swipe_dy)));
 if height-.18>3 and height+.18<12 then
   for i in 0..3 loop
     if abs(landing_x-(-15+i*10))+.18<4.2 then lane:=i; exit; end if;
   end loop;
 end if;
 kick_outcome:=case when lane is null then 'miss' when q.choices->lane->>'id'=q.correct_option_id then 'correct' else 'wrong' end;
 if kick_outcome='correct' then
   damage:=least(s.max_hp::numeric/16,s.hp); captured:=s.hp<=s.max_hp::numeric/16;
   update public.game_spots set hp=case when captured then max_hp else hp-damage end,
     owner_team_id=case when captured then a.team_id else owner_team_id end,
     capture_epoch=capture_epoch+case when captured then 1 else 0 end,
     revision=revision+1,updated_at=clock_timestamp() where id=s.id;
 end if;
 update app_private.attack_questions set resolved_at=clock_timestamp(),outcome=kick_outcome where id=q.id;
 update app_private.point_attacks set sequence=sequence+1,damage_dealt=damage_dealt+damage,last_outcome=kick_outcome,
   correct_count=correct_count+case when kick_outcome='correct' then 1 else 0 end,
   wrong_count=wrong_count+case when kick_outcome='wrong' then 1 else 0 end,
   miss_count=miss_count+case when kick_outcome='miss' then 1 else 0 end,
   status=case when captured then 'captured' when sequence+1>=4 then 'completed' else 'active' end where id=a.id;
 if not captured and a.sequence+1<4 then
   if exists(select 1 from app_private.question_bank b where b.active and b.is_test=s.is_test) then
     perform app_private.deal_attack_question(a.id);
   else
     update app_private.point_attacks set status='bank_unavailable' where id=a.id;
   end if;
 end if;
 result:=jsonb_build_object('outcome',kick_outcome,'lane',lane,'damage',damage,'captured',captured,'state',app_private.attack_payload(a.id));
 insert into app_private.attack_shots(attack_id,command_id,question_id,result) values(a.id,command_id,q.id,result);
 return result;
end;
$$;
revoke all on function public.submit_point_kick(uuid,uuid,uuid,double precision,double precision) from public,anon;
grant execute on function public.submit_point_kick(uuid,uuid,uuid,double precision,double precision) to authenticated;
notify pgrst,'reload schema';
commit;
