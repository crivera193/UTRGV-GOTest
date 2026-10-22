# Live REST integration against isolated QA point. No user location or real point mutation.
import socket,time,re
import json,urllib.request,urllib.error,uuid,datetime,concurrent.futures
from pathlib import Path
cfg=json.loads(Path('.env.app.local.json').read_text(encoding='utf-8-sig'))
f=json.loads(Path('output/team-e2e/fixture.json').read_text(encoding='utf-8-sig'))
assert cfg['SUPABASE_URL']=='https://oipidltfvzodpiumdsaq.supabase.co', 'Wrong project'
assert all(f[k].startswith('team-e2e-'+k+'-') and f[k].endswith('@example.edu') for k in ('a','b','c','d')), 'Synthetic accounts required'
base=cfg['SUPABASE_URL']; key=cfg.get('SUPABASE_PUBLISHABLE_KEY') or cfg.get('SUPABASE_ANON_KEY');spot='qa-live-attacks-20261022'
def req(path,data=None,token=None,method=None):
 h={'apikey':key,'Content-Type':'application/json'}
 if token:h['Authorization']='Bearer '+token
 r=urllib.request.Request(base+path,data=None if data is None else json.dumps(data).encode(),headers=h,method=method)
 try:
  with urllib.request.urlopen(r,timeout=50) as out:return out.status,json.loads(out.read() or b'null')
 except urllib.error.HTTPError as e:return e.code,json.loads(e.read())
def ok(path,data=None,token=None,method=None):
 status,value=req(path,data,token,method)
 assert status<300,(status,value)
 return value
def uid():return str(uuid.uuid4())
def begin(token,**extra):
 return ok('/rest/v1/rpc/begin_point_attack',{'spot_id':spot,'request_id':uid(),'latitude':0,'longitude':0,'accuracy_meters':0,'fix_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),**extra},token)
def shot(token,a,mode='correct',cmd=None,q=None):
 correct={'qa-live-add':'4','qa-live-shape':'3','qa-live-light':'Red','qa-live-safe':'Safe outdoor path'}[a['question']['bank_id']]
 lane=next(i for i,c in enumerate(a['question']['choices']) if c['text']==correct)
 if mode=='wrong':lane=(lane+1)%4
 return {'attack_id':a['id'],'question_id':q or a['question']['instance_id'],'command_id':cmd or uid(),'swipe_dx':0 if mode=='miss' else -90+lane*60,'swipe_dy':-180}

def dt(value):
 value=re.sub(r'\.(\d+)(?=[+-]|Z|$)',lambda m:'.'+m.group(1).ljust(6,'0')[:6],value)
 return datetime.datetime.fromisoformat(value)
tokens={};users={}
for who in ('a','b','c','d'):
 v=ok('/auth/v1/token?grant_type=password',{'email':f[who],'password':f['password']})
 tokens[who]=v['access_token'];users[who]=v['user']['id']
def read(token,a):return ok('/rest/v1/rpc/read_point_attack',{'attack_id':a['id']},token)
def attack_body():return {'spot_id':spot,'request_id':uid(),'latitude':0,'longitude':0,'accuracy_meters':0,'fix_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
def access(token):return ok('/rest/v1/rpc/point_attack_access',{'spot_id':spot},token)
def hit(token,a,mode='correct'):
 body=shot(token,a,mode);v=ok('/rest/v1/rpc/submit_point_kick',body,token)
 assert v['outcome']==mode,v
 assert ok('/rest/v1/rpc/submit_point_kick',body,token)==v,'Duplicate changed receipt'
 assert req('/rest/v1/rpc/submit_point_kick',{**body,'command_id':uid()},token)[0]==409
 return v['state']
evidence={}
spot='qa-timed-capture-v2-20261022'
for round,who in enumerate(('a','c','d','b')):
 a=begin(tokens[who]);start=a
 assert 14<= (dt(a['question']['due_at'])-dt(a['server_now'])).total_seconds()<=15
 assert a['questions_total']==4 and a['sequence']==0
 assert 'correct_option_id' not in json.dumps(a)
 resumed=begin(tokens[who]);assert resumed['id']==a['id'] and resumed['question']['instance_id']==a['question']['instance_id']
 seen=set()
 for question in range(4):
  seen.add(a['question']['bank_id']);a=hit(tokens[who],a)
 assert len(seen)==4,'Question repeated within four-question bank'
 assert a['damage_dealt']==25 and a['sequence']==4 and a['correct_count']==4
 assert a['status']==('captured' if round==3 else 'completed')
 assert a['point']['hp']==(100 if round==3 else 100-25*(round+1))
 if round<3:assert a['point']['owner_team_id'] is None
 assert req('/rest/v1/rpc/begin_point_attack',attack_body(),tokens[who])[0] in (429,403)
 limits=access(tokens[who]);assert limits['can_resume']==False
 assert 580<=(dt(limits['cooldown_until'])-dt(limits['server_now'])).total_seconds()<=600
 evidence[who]={'hp':a['point']['hp'],'damage':a['damage_dealt'],'status':a['status']}
assert a['point']['owner_team_id']=='math_engineering','Last attacker team did not win'
for who,token in tokens.items():
 shared=ok('/rest/v1/game_spots?id=eq.'+spot,None,token)[0]
 assert shared['owner_team_id']=='math_engineering' and shared['hp']==100
 assert len(ok('/rest/v1/player_profiles?id=eq.'+users[who],None,token))==1
 team=ok('/rest/v1/account_teams?user_id=eq.'+users[who],None,token)[0]['team_id']
 assert team==('math_engineering' if who=='b' else 'art_stuff')
print('PASS: four accounts each capped at 25%; first three cannot capture; final Math and Engineering attacker owns point for all clients; profiles/teams intact.',flush=True)
spot='qa-timed-race-20261022';a=begin(tokens['a']);body=shot(tokens['a'],a)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 results=list(pool.map(lambda _:req('/rest/v1/rpc/submit_point_kick',{**body,'command_id':uid()},tokens['a']),range(2)))
assert sorted(s for s,_ in results)==[200,409],results
a=read(tokens['a'],a);assert a['point']['hp']==93.75 and a['sequence']==1
assert req('/rest/v1/rpc/read_point_attack',{'attack_id':a['id']},tokens['b'])[0]==403
assert req('/rest/v1/game_spots?id=eq.'+spot,{'hp':0},tokens['a'],'PATCH')[0]==403
assert req('/rest/v1/rpc/point_attack_access',{'spot_id':spot},None)[0] in (401,403)
for _ in range(3):a=hit(tokens['a'],a,'miss')
assert a['status']=='completed' and a['damage_dealt']==6.25
print('PASS: duplicate/stale/concurrent submissions cannot multiply damage; all results consume exactly one of four questions.',flush=True)
spot='qa-timed-partial-20261022';a=begin(tokens['a'])
a=hit(tokens['a'],a,'correct');a=hit(tokens['a'],a,'wrong');a=hit(tokens['a'],a,'correct')
remaining=(dt(a['question']['due_at'])-dt(a['server_now'])).total_seconds()
print('Waiting for one real 15-second server deadline...',flush=True)
time.sleep(max(0,remaining)+.3)
late=ok('/rest/v1/rpc/submit_point_kick',shot(tokens['a'],a),tokens['a'])
assert late['outcome']=='timeout' and late['damage']==0
ended=read(tokens['a'],a)
assert ended['status']=='completed' and ended['sequence']==4 and ended['timeout_count']==1
assert ended['correct_count']==2 and ended['wrong_count']==1 and ended['damage_dealt']==12.5 and ended['point']['hp']==87.5
assert req('/rest/v1/rpc/begin_point_attack',attack_body(),tokens['a'])[0]==429
print('PASS: partial score is exactly 12.5%; real timeout rejects a late correct kick and completes the attempt; cooldown blocks a fresh request.',flush=True)
spot='qa-timed-boundary-20261022';a=begin(tokens['a'])
for _ in range(4):a=hit(tokens['a'],a,'miss')
evidence['boundary_attack_id']=a['id'];evidence['actor']=users['a']
Path('output/team-e2e/timed').mkdir(exist_ok=True)
Path('output/team-e2e/timed/rest-evidence.json').write_text(json.dumps(evidence,indent=2))
real=ok('/rest/v1/game_spots?id=eq.echap-local-v1',None,tokens['a'])[0]
assert real['hp']==100 and real['owner_team_id'] is None and real['revision']==0
print('PASS: real chapel remains untouched; boundary fixture ready.',flush=True)
