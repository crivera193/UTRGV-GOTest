-- Reconcile offline deadlines before reporting trainer counters, with the established actor/point lock order.
begin;
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
notify pgrst,'reload schema';
commit;
