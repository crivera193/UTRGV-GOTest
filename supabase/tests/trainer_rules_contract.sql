-- Live SQL contract: all synthetic data and configuration edits roll back.
begin;
do $$
declare actor uuid:=gen_random_uuid(); point_key text:='qa-trainer-contract-'||gen_random_uuid();
 attack jsonb; result jsonb; trainer jsonb; aid uuid; lane integer;
begin
 insert into auth.users(id,email,aud,role,raw_app_meta_data) values(actor,'trainer-contract-'||actor||'@example.edu','authenticated','authenticated','{"live_game_test":true}');
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform public.choose_team('health_science');
 insert into public.game_spots(id,name,latitude,longitude,is_test) values(point_key,'QA rolled-back trainer',0,0,true);
 update public.progression_settings set correct_xp=37 where id;
 attack:=public.begin_point_attack(point_key,gen_random_uuid(),0::double precision,0::double precision,0::double precision,clock_timestamp()-interval '500 milliseconds');
 aid:=(attack->>'id')::uuid;
 update public.progression_settings set correct_xp=99 where id;
 select v.ord-1 into lane from app_private.attack_questions q,
 jsonb_array_elements(q.choices) with ordinality v(c,ord)
 where q.id=(attack->'question'->>'instance_id')::uuid and v.c->>'id'=q.correct_option_id;
 result:=public.submit_point_kick(aid,(attack->'question'->>'instance_id')::uuid,gen_random_uuid(),(-90+lane*60)::double precision,-180::double precision);
 if result->>'outcome'<>'correct' then raise exception 'Contract kick missed';end if;
 if (select xp from public.player_progress where user_id=actor)<>37 then raise exception 'Reward snapshot changed during attempt';end if;
 update app_private.attack_questions set due_at=clock_timestamp()-interval '60 seconds' where id=(result->'state'->'question'->>'instance_id')::uuid;
 trainer:=public.read_trainer();
 if trainer->'progress'->>'completed_attacks'<>'1' or trainer->'progress'->>'xp'<>'37' then raise exception 'Profile did not reconcile offline attempt';end if;
 result:=public.read_point_attack(aid);
 if result->>'timeout_count'<>'3' or result->>'xp_earned'<>'37' then raise exception 'Timeouts or earned XP feedback incorrect';end if;
 insert into public.progression_achievements(id,title,description,kind,metric,target) values('qa-rolled-back-badge','Live configured badge','Contract only','badge','correct_kicks',1);
 update public.progression_levels set min_xp=20 where level=2;
 update public.progression_ranks set name='Live configured rank' where min_level=1;
 trainer:=public.read_trainer();
 if not exists(select 1 from public.player_achievements where user_id=actor and achievement_id='qa-rolled-back-badge') then raise exception 'Dynamic milestone not evaluated';end if;
 if not exists(select 1 from jsonb_array_elements(trainer->'levels') l where l->>'level'='2' and l->>'min_xp'='20') then raise exception 'Dynamic level not returned';end if;
 if not exists(select 1 from jsonb_array_elements(trainer->'ranks') r where r->>'name'='Live configured rank') then raise exception 'Dynamic rank not returned';end if;
 if has_function_privilege('authenticated','app_private.award_trainer_event(uuid,uuid,text,integer,text)','EXECUTE')
 or has_function_privilege('authenticated','app_private.evaluate_trainer_achievements(uuid)','EXECUTE')
 or has_table_privilege('authenticated','app_private.player_xp_events','INSERT') then raise exception 'Client reward privilege leaked';end if;
end;$$;
select 'PASS: immutable reward snapshot, offline catch-up, earned XP feedback, configurable levels/ranks/milestones and private reward helpers' as contract;
rollback;
