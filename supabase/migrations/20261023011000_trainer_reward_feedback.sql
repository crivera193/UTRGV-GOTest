begin;
create or replace function app_private.attack_payload(aid uuid) returns jsonb
language sql volatile security definer set search_path='' as $$
 select jsonb_build_object('id',a.id,'spot_id',a.spot_id,'team_id',a.team_id,'status',a.status,
 'sequence',a.sequence,'questions_total',(a.rules_snapshot->>'questions_total')::int,'rules',a.rules_snapshot,'correct_count',a.correct_count,'wrong_count',a.wrong_count,
 'miss_count',a.miss_count,'timeout_count',a.timeout_count,'damage_dealt',a.damage_dealt,'last_outcome',a.last_outcome,
 'expires_at',a.expires_at,'server_now',clock_timestamp(),'cooldown_until',a.cooldown_until,
 'point',(to_jsonb(s)-'is_test')||jsonb_build_object('rules',to_jsonb(r)),
 'xp_earned',(select coalesce(sum(e.xp),0) from app_private.player_xp_events e where e.attack_id=a.id),
 'question',jsonb_build_object('instance_id',q.id,'bank_id',q.bank_id,'version',q.bank_version,
 'prompt',q.prompt,'choices',q.choices,'due_at',q.due_at))
 from app_private.point_attacks a join public.game_spots s on s.id=a.spot_id
 join public.game_rule_sets r on r.id=s.rule_set_id
 left join app_private.attack_questions q on q.id=a.current_question_id where a.id=aid;
$$;
revoke all on function app_private.attack_payload(uuid) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
