-- Preset-only family-friendly avatars. Keep old private objects, disable all client upload/read paths.
begin;
create table public.trainer_avatars (
 id text primary key,label text not null,
 design text not null check(design in ('cat','fox','owl','robot','cactus','cowboy')),
 background text not null check(background ~ '^#[0-9A-Fa-f]{6}$'),
 accent text not null check(accent ~ '^#[0-9A-Fa-f]{6}$'),
 enabled boolean not null default true,sort_order integer not null default 0
);
insert into public.trainer_avatars(id,label,design,background,accent,sort_order) values
 ('cowboy','Cowboy','cowboy','#DDEBDD','#9A572F',1),
 ('cat','Cat','cat','#F9E4CC','#D6A05C',2),
 ('fox','Fox','fox','#E2EDF8','#E9893D',3),
 ('owl','Owl','owl','#EDE3F6','#9270B3',4),
 ('robot','Robot','robot','#E0F0F0','#50989B',5),
 ('cactus','Cactus','cactus','#FAE8D4','#4D9569',6);
alter table public.trainer_avatars enable row level security;
revoke all on public.trainer_avatars from public,anon,authenticated;
grant select on public.trainer_avatars to authenticated;
create policy edu_read_trainer_avatars on public.trainer_avatars for select to authenticated using((select app_private.is_edu_player()));
alter table public.player_profiles add column avatar_id text not null default 'cowboy' references public.trainer_avatars(id);
drop policy trainer_avatar_insert on storage.objects;
drop policy trainer_avatar_read on storage.objects;
drop policy trainer_avatar_delete on storage.objects;
create or replace function public.update_trainer_profile(trainer_username text,trainer_name text,trainer_bio text,trainer_avatar text,expected_revision bigint)
 returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();p public.player_profiles;clean text:=lower(btrim(trainer_username));
begin
 if actor is null or not app_private.is_edu_player() then raise exception 'Sign in required.' using errcode='42501';end if;
 if clean is null or clean !~ '^[a-z][a-z0-9_]{2,19}$' or trainer_name is null or trainer_bio is null
 or length(btrim(trainer_name))>32 or length(btrim(trainer_bio))>200 then
 raise exception 'Use a 3–20 character username starting with a letter; name max 32 and bio max 200 characters.' using errcode='22023';end if;
 if trainer_avatar is null or not exists(select 1 from public.trainer_avatars where id=trainer_avatar and enabled) then
 raise exception 'Choose an available preset avatar.' using errcode='22023';end if;
 update public.player_profiles set username=clean,display_name=btrim(trainer_name),bio=btrim(trainer_bio),avatar_id=trainer_avatar,
 revision=revision+1,updated_at=clock_timestamp() where id=actor and revision=expected_revision returning * into p;
 if p.id is null then raise exception 'Your profile changed on another session. Refresh before saving.' using errcode='PT409';end if;
 return to_jsonb(p)||jsonb_build_object('avatar_path',null);
exception when unique_violation then raise exception 'That username is already taken.' using errcode='PT409';
end;$$;
revoke all on function public.update_trainer_profile(text,text,text,text,bigint) from public,anon,authenticated;
grant execute on function public.update_trainer_profile(text,text,text,text,bigint) to authenticated;

create or replace function public.read_trainer() returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=auth.uid();result jsonb; running record;
begin
 if actor is null or not app_private.is_edu_player() then raise exception 'Sign in required.' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended(actor::text,7241));
 for running in select id,spot_id from app_private.point_attacks where user_id=actor and status='active' order by spot_id loop
 perform 1 from public.game_spots where id=running.spot_id for update;
 perform app_private.advance_timed_attack(running.id);
 end loop;
 insert into public.player_progress(user_id) values(actor) on conflict do nothing;
 perform app_private.evaluate_trainer_achievements(actor);
 select jsonb_build_object('profile',to_jsonb(p)||jsonb_build_object('avatar_path',null),'progress',to_jsonb(g),
 'avatars',(select coalesce(jsonb_agg(to_jsonb(v) order by v.sort_order,v.id),'[]'::jsonb) from public.trainer_avatars v where v.enabled or v.id=p.avatar_id),
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
alter publication supabase_realtime add table public.trainer_avatars;
notify pgrst,'reload schema';
commit;
