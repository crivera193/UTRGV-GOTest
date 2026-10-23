"""Phased live QA. Apply dynamic_points_fixture.sql once before 'start'."""
import sys
from pathlib import Path
exec(Path('test_driver/live_attack_rest.py').read_text().split('tokens={};users={}')[0])
tokens = {}
for who in ('a', 'b', 'c', 'd'):
    tokens[who] = ok('/auth/v1/token?grant_type=password', {'email':f[who], 'password':f['password']})['access_token']
out = Path('output/team-e2e/dynamic'); out.mkdir(parents=True, exist_ok=True)
def read(a, who='a'):
    return ok('/rest/v1/rpc/read_point_attack', {'attack_id':a['id']}, tokens[who])
def hit(a, who='a', mode='correct'):
    body = shot(tokens[who], a, mode)
    receipt = ok('/rest/v1/rpc/submit_point_kick', body, tokens[who])
    assert receipt['outcome'] == mode, receipt
    assert ok('/rest/v1/rpc/submit_point_kick', body, tokens[who]) == receipt
    return receipt['state']
def start(point, who='a'):
    return begin(tokens[who], spot_id=point)
phase = sys.argv[1]
if phase == 'start':
    # Keep custom attempt live across an admin rule edit.
    a = start('qa-dynamic-custom-20261022')
    assert a['rules']['questions_total']==7 and a['rules']['question_seconds']==120
    assert a['rules']['max_damage_percent']==30 and a['rules']['cooldown_seconds']==180
    moves = {kind:start('qa-dynamic-'+kind+'-20261022') for kind in ('move','disable')}
    (out/'pending.json').write_text(json.dumps({'custom':a, **moves}))
    print('PASS: live custom rules and point definitions loaded; active snapshots saved.', flush=True)
elif phase == 'edited':
    saved=json.loads((out/'pending.json').read_text())
    a=read(saved['custom']); assert a['status']=='active',a
    assert a['rules']['questions_total']==7 and a['point']['rules']['questions_total']==3
    assert a['cooldown_until']==saved['custom']['cooldown_until']
    seen=set()
    for i in range(7):
        seen.add(a['question']['bank_id']); a=hit(a)
    assert len(seen)==4 and a['status']=='completed'
    assert a['damage_dealt']==36 and a['point']['hp']==84, a
    # New actor sees the edited rules, old actor retains the original cooldown.
    b=start('qa-dynamic-custom-20261022','b')
    assert b['rules']['questions_total']==3 and b['rules']['question_seconds']==8
    assert b['rules']['max_damage_percent']==40 and b['rules']['cooldown_seconds']==60
    b=hit(b,'b'); b=hit(b,'b','wrong'); b=hit(b,'b','miss')
    assert b['damage_dealt']==16 and b['sequence']==3 and b['point']['hp']==68,b
    cooldown=ok('/rest/v1/rpc/point_attack_access',{'spot_id':a['spot_id']},tokens['a'])
    assert cooldown['cooldown_until']==saved['custom']['cooldown_until']
    for kind in ('move','disable'):
        ended=read(saved[kind]); assert ended['status']=='superseded' and ended['damage_dealt']==0
        assert req('/rest/v1/rpc/submit_point_kick',shot(tokens['a'],saved[kind]),tokens['a'])[0]==409
    # Re-enabled/moved IDs retain attempt history and entry cooldown.
    assert req('/rest/v1/game_rule_sets?id=eq.standard',{'questions_total':1},tokens['a'],'PATCH')[0]==403
    assert req('/rest/v1/game_spots?id=eq.'+a['spot_id'],{'hp':0},tokens['a'],'PATCH')[0]==403
    assert 'correct_option_id' not in json.dumps(a)
    (out/'custom-results.json').write_text(json.dumps({'original':a,'edited':b,'invalidated':True,'permissions':True},indent=2))
    print('PASS: old snapshot/cooldown preserved; 7-question rounding exact at 36/120 HP; new 3-question rules deal 16 HP per correct kick; wrong/miss zero; move/disable ends attacks; writes/answer keys protected.',flush=True)
elif phase == 'capture':
    rows=[]
    for index,who in enumerate(('a','c','d','b')):
        a=start('qa-dynamic-capture-20261022',who)
        assert a['questions_total']==4 and a['rules']['question_seconds']==15
        assert a['rules']['cooldown_seconds']==600 and a['rules']['max_damage_percent']==25
        for _ in range(4): a=hit(a,who)
        assert a['damage_dealt']==25 and a['sequence']==4
        assert a['status']==('captured' if index==3 else 'completed')
        assert a['point']['hp']==(100 if index==3 else 100-(index+1)*25)
        rows.append({'actor':who,'hp':a['point']['hp'],'status':a['status']})
    for who in tokens:
        shared=ok('/rest/v1/game_spots?id=eq.'+a['spot_id'],token=tokens[who])[0]
        assert shared['owner_team_id']=='math_engineering' and shared['hp']==100
    (out/'four-account-capture.json').write_text(json.dumps(rows,indent=2))
    print('PASS: standard defaults unchanged; four real accounts capture in 25% steps; final attacker team and restored full HP agree across clients.',flush=True)
else:
    raise ValueError('Unknown phase')
