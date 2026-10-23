-- UTRGV-GO only. Profile edits and progression are account-scoped and server owned.
begin;
alter table public.player_profiles
 add column username text unique check(username ~ '^[a-z][a-z0-9_]{2,19}$'),
 add column display_name text not null default '' check(length(display_name)<=32),
 add column bio text not null default '' check(length(bio)<=200),
 add column avatar_path text,
 add column revision bigint not null default 0,
 add column updated_at timestamptz not null default clock_timestamp();

create table public.progression_settings (
 id boolean primary key default true check(id),
 correct_xp integer not null check(correct_xp between 0 and 10000),
 perfect_xp integer not null check(perfect_xp between 0 and 10000),
 capture_xp integer not null check(capture_xp between 0 and 10000)
);
insert into public.progression_settings values(true,25,50,100);
create table public.progression_levels (
 level integer primary key check(level>0), min_xp bigint unique not null check(min_xp>=0)
);
insert into public.progression_levels select n,100::bigint*(n-1)*(n-1) from generate_series(1,20) n;
create table public.progression_ranks (
 id text primary key,name text not null,min_level integer unique not null check(min_level>0)
);
insert into public.progression_ranks values ('newcomer','Newcomer',1),('scout','Campus Scout',3),
 ('trailblazer','Trailblazer',5),('guardian','Campus Guardian',10),('legend','Campus Legend',20);
create table public.progression_achievements (
 id text primary key,title text not null,description text not null,
 kind text not null check(kind in ('badge','achievement')),
 metric text not null check(metric in ('correct_kicks','captures','perfect_attacks','completed_attacks','xp')),
 target bigint not null check(target>0), emblem text not null default '★',enabled boolean not null default true,
 sort_order integer not null default 0
);
insert into public.progression_achievements(id,title,description,kind,metric,target,emblem,sort_order) values
 ('first-kick','First on Target','Land your first correct kick.','achievement','correct_kicks',1,'◎',1),
 ('ten-correct','Sharp Shooter','Land 10 correct kicks.','badge','correct_kicks',10,'🎯',2),
 ('hundred-correct','Knowledge Keeper','Land 100 correct kicks.','badge','correct_kicks',100,'📚',3),
 ('first-perfect','Clean Sweep','Answer every question correctly in an attack.','achievement','perfect_attacks',1,'★',4),
 ('ten-perfect','Precision Player','Complete 10 perfect attacks.','badge','perfect_attacks',10,'✦',5),
 ('first-capture','Flag Bearer','Deliver the final hit to capture a point for your team.','achievement','captures',1,'⚑',6),
 ('ten-captures','Campus Champion','Capture 10 points for your team.','badge','captures',10,'🏆',7),
 ('ten-attacks','Committed Explorer','Finish 10 attacks.','achievement','completed_attacks',10,'◇',8);
create table public.player_progress (
 user_id uuid primary key references auth.users(id),xp bigint not null default 0 check(xp>=0),
 correct_kicks bigint not null default 0,captures bigint not null default 0,
 perfect_attacks bigint not null default 0,completed_attacks bigint not null default 0,
 revision bigint not null default 0
);
create table public.player_achievements (
 user_id uuid not null references auth.users(id),achievement_id text not null references public.progression_achievements(id),
 earned_at timestamptz not null default clock_timestamp(),primary key(user_id,achievement_id)
);
create table app_private.player_xp_events (
 user_id uuid not null references auth.users(id),event_key text not null,
 attack_id uuid not null references app_private.point_attacks(id),xp integer not null check(xp>=0),
 reason text not null,created_at timestamptz not null default clock_timestamp(),primary key(user_id,event_key)
);
alter table app_private.player_xp_events enable row level security;
revoke all on app_private.player_xp_events from public,anon,authenticated;
do $$declare t text;begin
 foreach t in array array['progression_settings','progression_levels','progression_ranks','progression_achievements','player_progress','player_achievements'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 if t in ('player_progress','player_achievements') then
 execute format('create policy own_trainer_data on public.%I for select to authenticated using(user_id=(select auth.uid()) and (select app_private.is_edu_player()))',t);
 else
 execute format('create policy edu_progression_catalog on public.%I for select to authenticated using((select app_private.is_edu_player()))',t);
 end if;
 end loop;
end;$$;

-- Private avatars: unique immutable filenames; no public bucket and no cross-account reads.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
 values('trainer-avatars','trainer-avatars',false,2097152,array['image/jpeg']);
create policy trainer_avatar_read on storage.objects for select to authenticated
 using(bucket_id='trainer-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text and (select app_private.is_edu_player()));
create policy trainer_avatar_insert on storage.objects for insert to authenticated
 with check(bucket_id='trainer-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text and (select app_private.is_edu_player()));
create policy trainer_avatar_delete on storage.objects for delete to authenticated
 using(bucket_id='trainer-avatars' and (storage.foldername(name))[1]=(select auth.uid())::text and (select app_private.is_edu_player()));

create function public.update_trainer_profile(trainer_username text,trainer_name text,trainer_bio text,trainer_avatar text,expected_revision bigint)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();p public.player_profiles;clean text:=lower(btrim(trainer_username));
begin
 if actor is null or not app_private.is_edu_player() then raise exception 'Sign in required.' using errcode='42501';end if;
 if clean is null or clean !~ '^[a-z][a-z0-9_]{2,19}$' or trainer_name is null or trainer_bio is null
 or length(btrim(trainer_name))>32 or length(btrim(trainer_bio))>200 then
 raise exception 'Use a 3–20 character username starting with a letter; name max 32 and bio max 200 characters.' using errcode='22023';end if;
 if trainer_avatar is not null and not exists(select 1 from storage.objects o where o.bucket_id='trainer-avatars'
 and o.name=trainer_avatar and (storage.foldername(o.name))[1]=actor::text) then
 raise exception 'Upload a photo to your own avatar folder first.' using errcode='42501';end if;
 update public.player_profiles set username=clean,display_name=btrim(trainer_name),bio=btrim(trainer_bio),avatar_path=trainer_avatar,
 revision=revision+1,updated_at=clock_timestamp() where id=actor and revision=expected_revision returning * into p;
 if p.id is null then raise exception 'Your profile changed on another session. Refresh before saving.' using errcode='PT409';end if;
 return to_jsonb(p);
exception when unique_violation then raise exception 'That username is already taken.' using errcode='PT409';
end;$$;
revoke all on function public.update_trainer_profile(text,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.update_trainer_profile(text,text,text,text,bigint) to authenticated;

create function app_private.evaluate_trainer_achievements(actor uuid) returns void
 language sql security definer set search_path='' as $$
 insert into public.player_achievements(user_id,achievement_id)
 select actor,a.id from public.progression_achievements a join public.player_progress p on p.user_id=actor
 where a.enabled and coalesce((to_jsonb(p)->>a.metric)::bigint,0)>=a.target
 on conflict(user_id,achievement_id) do nothing;
$$;
revoke all on function app_private.evaluate_trainer_achievements(uuid) from public,anon,authenticated;
alter table app_private.point_attacks add column rewards_snapshot jsonb;
update app_private.point_attacks set rewards_snapshot=(select to_jsonb(s) from public.progression_settings s);
alter table app_private.point_attacks alter column rewards_snapshot set not null;
create function app_private.snapshot_trainer_rewards() returns trigger language plpgsql security definer set search_path='' as $$
begin
 select to_jsonb(s) into new.rewards_snapshot from public.progression_settings s where id;
 if new.rewards_snapshot is null then raise exception 'Progression settings unavailable.';end if;
 return new;
end;$$;
revoke all on function app_private.snapshot_trainer_rewards() from public,anon,authenticated;
create trigger snapshot_trainer_rewards before insert on app_private.point_attacks for each row execute function app_private.snapshot_trainer_rewards();

create function app_private.award_trainer_event(actor uuid,aid uuid,ekey text,amount integer,kind text)
 returns void language plpgsql security definer set search_path='' as $$
declare added integer;
begin
 insert into app_private.player_xp_events(user_id,attack_id,event_key,xp,reason) values(actor,aid,ekey,amount,kind)
 on conflict(user_id,event_key) do nothing;
 get diagnostics added=row_count;
 if added=0 then return;end if;
 insert into public.player_progress(user_id,xp,correct_kicks,captures,perfect_attacks,completed_attacks,revision)
 values(actor,amount,(kind='correct')::int,(kind='capture')::int,(kind='perfect')::int,(kind='complete')::int,1)
 on conflict(user_id) do update set xp=player_progress.xp+excluded.xp,
 correct_kicks=player_progress.correct_kicks+excluded.correct_kicks,captures=player_progress.captures+excluded.captures,
 perfect_attacks=player_progress.perfect_attacks+excluded.perfect_attacks,completed_attacks=player_progress.completed_attacks+excluded.completed_attacks,
 revision=player_progress.revision+1;
 perform app_private.evaluate_trainer_achievements(actor);
end;$$;
revoke all on function app_private.award_trainer_event(uuid,uuid,text,integer,text) from public,anon,authenticated;
create function app_private.trainer_attack_rewards() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.correct_count>old.correct_count then
 perform app_private.award_trainer_event(new.user_id,new.id,new.id::text||':correct:'||new.correct_count,
 (new.rewards_snapshot->>'correct_xp')::int,'correct');end if;
 if new.status in ('completed','captured') and old.status='active' then
 perform app_private.award_trainer_event(new.user_id,new.id,new.id::text||':complete',0,'complete');
 if new.correct_count=(new.rules_snapshot->>'questions_total')::int then
 perform app_private.award_trainer_event(new.user_id,new.id,new.id::text||':perfect',
 (new.rewards_snapshot->>'perfect_xp')::int,'perfect');end if;
 if new.status='captured' then
 perform app_private.award_trainer_event(new.user_id,new.id,new.id::text||':capture',
 (new.rewards_snapshot->>'capture_xp')::int,'capture');end if;
 end if;
 return new;
end;$$;
revoke all on function app_private.trainer_attack_rewards() from public,anon,authenticated;
create trigger trainer_attack_rewards after update on app_private.point_attacks for each row execute function app_private.trainer_attack_rewards();

create function public.read_trainer() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();result jsonb;
begin
 if actor is null or not app_private.is_edu_player() then raise exception 'Sign in required.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,7241));
 insert into public.player_progress(user_id) values(actor) on conflict do nothing;
 perform app_private.evaluate_trainer_achievements(actor);
 select jsonb_build_object('profile',to_jsonb(p),'progress',to_jsonb(g),
 'levels',(select coalesce(jsonb_agg(to_jsonb(l) order by l.min_xp),'[]'::jsonb) from public.progression_levels l),
 'ranks',(select coalesce(jsonb_agg(to_jsonb(r) order by r.min_level),'[]'::jsonb) from public.progression_ranks r),
 'settings',(select to_jsonb(s) from public.progression_settings s where id),
 'achievements',(select coalesce(jsonb_agg(to_jsonb(a)||jsonb_build_object('earned_at',e.earned_at,'value',coalesce((to_jsonb(g)->>a.metric)::bigint,0)) order by a.sort_order,a.id),'[]'::jsonb)
 from public.progression_achievements a left join public.player_achievements e on e.user_id=actor and e.achievement_id=a.id where a.enabled))
 into result from public.player_profiles p join public.player_progress g on g.user_id=p.id where p.id=actor;
 return result;
end;$$;
revoke all on function public.read_trainer() from public,anon,authenticated;
grant execute on function public.read_trainer() to authenticated;
alter publication supabase_realtime add table public.progression_settings,public.progression_levels,public.progression_ranks,
 public.progression_achievements,public.player_progress,public.player_achievements,public.player_profiles;
notify pgrst,'reload schema';
commit;
