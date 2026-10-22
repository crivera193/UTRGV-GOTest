-- Live UTRGV-GO only (oipidltfvzodpiumdsaq). Additive; no device-save import.
begin;
create table app_private.question_bank (
  id text primary key,
  prompt text not null check (length(prompt) between 5 and 500),
  choices text[] not null check (array_length(choices,1)=4 and array_position(choices,null) is null),
  correct_index smallint not null check (correct_index between 0 and 3),
  active boolean not null default true,
  is_test boolean not null default false,
  version integer not null default 1 check(version>0)
);
comment on table app_private.question_bank is 'Admin-authored bank. Never expose answers or this table through client grants. Attack questions are immutable snapshots.';
insert into app_private.question_bank(id,prompt,choices,correct_index) values
 ('placeholder-addition','Placeholder question · What is 2 + 2?',array['4','3','5','6'],0),
 ('placeholder-shape','Placeholder question · How many sides does a triangle have?',array['2','3','4','5'],1),
 ('placeholder-color','Placeholder question · Which is a primary color of light?',array['Brown','Black','Red','Gray'],2),
 ('placeholder-safety','Placeholder question · Where should you stop to play?',array['In a road','On stairs','While crossing traffic','A safe outdoor path'],3);

create table public.game_spots (
  id text primary key, name text not null,
  latitude double precision not null check(latitude between -90 and 90),
  longitude double precision not null check(longitude between -180 and 180),
  attack_meters double precision not null default 39.624 check(attack_meters>0 and attack_meters<=100),
  owner_team_id text references public.game_teams(id),
  hp integer not null default 100, max_hp integer not null default 100 check(max_hp>0),
  revision bigint not null default 0, capture_epoch bigint not null default 0,
  enabled boolean not null default true, is_test boolean not null default false,
  updated_at timestamptz not null default now(),
  check(hp>0 and hp<=max_hp)
);
insert into public.game_spots(id,name,latitude,longitude) values
 ('echap-local-v1','Chapel Point',26.305357,-98.174683);
comment on table public.game_spots is 'Shared authoritative point state. Initial live chapel is unclaimed; inconsistent former device-local saves are neither uploaded nor remapped.';

create table app_private.point_attacks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  spot_id text not null references public.game_spots(id),
  team_id text not null references public.game_teams(id),
  request_id uuid not null,
  capture_epoch bigint not null,
  status text not null default 'active' check(status in ('active','captured','superseded','expired','bank_unavailable')),
  current_question_id uuid,
  sequence integer not null default 0,
  correct_count integer not null default 0,
  wrong_count integer not null default 0,
  miss_count integer not null default 0,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '15 minutes',
  unique(user_id,request_id)
);
create unique index one_active_point_attack on app_private.point_attacks(user_id,spot_id) where status='active';
create table app_private.attack_questions (
  id uuid primary key default gen_random_uuid(),
  attack_id uuid not null references app_private.point_attacks(id),
  bank_id text not null references app_private.question_bank(id),
  bank_version integer not null,
  prompt text not null,
  choices jsonb not null,
  correct_option_id text not null,
  created_at timestamptz not null default now()
);
alter table app_private.point_attacks add constraint attack_current_question_fk
 foreign key(current_question_id) references app_private.attack_questions(id);
create table app_private.attack_shots (
  attack_id uuid not null references app_private.point_attacks(id),
  command_id uuid not null,
  question_id uuid not null unique references app_private.attack_questions(id),
  result jsonb not null,
  created_at timestamptz not null default now(),
  primary key(attack_id,command_id)
);
revoke all on app_private.question_bank,app_private.point_attacks,app_private.attack_questions,app_private.attack_shots from public,anon,authenticated;
alter table app_private.question_bank enable row level security;
alter table app_private.point_attacks enable row level security;
alter table app_private.attack_questions enable row level security;
alter table app_private.attack_shots enable row level security;
alter table public.game_spots enable row level security;
revoke all on public.game_spots from public,anon,authenticated;
grant select on public.game_spots to authenticated;

create function app_private.live_test_player() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.users where id=auth.uid()
 and raw_app_meta_data @> '{"live_game_test":true}'::jsonb);
$$;
revoke all on function app_private.live_test_player() from public,anon;
grant execute on function app_private.live_test_player() to authenticated;
create policy edu_players_read_live_spots on public.game_spots for select to authenticated
 using ((select app_private.is_edu_player()) and (not is_test or (select app_private.live_test_player())));

create function app_private.attack_payload(aid uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('id',a.id,'spot_id',a.spot_id,'team_id',a.team_id,'status',a.status,
 'sequence',a.sequence,'correct_count',a.correct_count,'wrong_count',a.wrong_count,'miss_count',a.miss_count,
 'expires_at',a.expires_at,'point',to_jsonb(s)-'is_test',
 'question',jsonb_build_object('instance_id',q.id,'bank_id',q.bank_id,'version',q.bank_version,'prompt',q.prompt,'choices',q.choices))
 from app_private.point_attacks a join public.game_spots s on s.id=a.spot_id
 left join app_private.attack_questions q on q.id=a.current_question_id where a.id=aid;
$$;
revoke all on function app_private.attack_payload(uuid) from public,anon,authenticated;

create function app_private.deal_attack_question(aid uuid) returns void
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
 order by (b.id=prev) asc nulls first,random() limit 1;
 if bank.id is null then raise exception 'No active questions are available. Please try later.' using errcode='P0001'; end if;
 select jsonb_agg(jsonb_build_object('id',(i-1)::text,'text',bank.choices[i]) order by random())
 into shuffled from generate_series(1,4) i;
 insert into app_private.attack_questions(attack_id,bank_id,bank_version,prompt,choices,correct_option_id)
 values(aid,bank.id,bank.version,bank.prompt,shuffled,bank.correct_index::text) returning id into chosen;
 update app_private.point_attacks set current_question_id=chosen where id=aid;
end;
$$;
revoke all on function app_private.deal_attack_question(uuid) from public,anon,authenticated;

create function public.begin_point_attack(spot_id text,request_id uuid,latitude double precision,longitude double precision,
 accuracy_meters double precision,fix_at timestamptz) returns jsonb
language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid(); team text; spot public.game_spots; a app_private.point_attacks; distance_m double precision;
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
   if a.capture_epoch=spot.capture_epoch and a.expires_at>now() then return app_private.attack_payload(a.id); end if;
   update app_private.point_attacks set status=case when expires_at<=now() then 'expired' else 'superseded' end where id=a.id;
 end if;
 insert into app_private.point_attacks(user_id,spot_id,team_id,request_id,capture_epoch)
 values(actor,spot.id,team,request_id,spot.capture_epoch) returning * into a;
 perform app_private.deal_attack_question(a.id);
 return app_private.attack_payload(a.id);
end;
$$;
revoke all on function public.begin_point_attack(text,uuid,double precision,double precision,double precision,timestamptz) from public,anon;
grant execute on function public.begin_point_attack(text,uuid,double precision,double precision,double precision,timestamptz) to authenticated;

create function public.read_point_attack(attack_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare a app_private.point_attacks; s public.game_spots; spot_key text;
begin
 if auth.uid() is null or not app_private.is_edu_player() then raise exception 'Sign in required.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,7241));
 select spot_id into spot_key from app_private.point_attacks where id=attack_id and user_id=auth.uid();
 select * into s from public.game_spots where id=spot_key for update;
 select * into a from app_private.point_attacks where id=attack_id and user_id=auth.uid() for update;
 if a.id is null then raise exception 'Attack unavailable.' using errcode='42501'; end if;
 if a.status='active' and (a.expires_at<=now() or a.capture_epoch<>s.capture_epoch) then
   update app_private.point_attacks set status=case when expires_at<=now() then 'expired' else 'superseded' end where id=a.id;
 end if;
 return app_private.attack_payload(a.id);
end;
$$;
revoke all on function public.read_point_attack(uuid) from public,anon;
grant execute on function public.read_point_attack(uuid) to authenticated;

create function public.submit_point_kick(attack_id uuid,question_id uuid,command_id uuid,
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
   raise exception 'This attack has ended or the point changed. Return to the map.' using errcode='40001'; end if;
 if a.current_question_id is distinct from question_id then raise exception 'This question was already resolved. Refresh the attack.' using errcode='40001'; end if;
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
alter publication supabase_realtime add table public.game_spots;
notify pgrst,'reload schema';
commit;
