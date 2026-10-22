# Live REST integration against isolated QA point. No user location or real point mutation.
import socket,time
import json,urllib.request,urllib.error,uuid,datetime,concurrent.futures
from pathlib import Path
cfg=json.loads(Path('.env.app.local.json').read_text(encoding='utf-8-sig'))
f=json.loads(Path('output/team-e2e/fixture.json').read_text(encoding='utf-8-sig'))
assert cfg['SUPABASE_URL']=='https://oipidltfvzodpiumdsaq.supabase.co', 'Wrong project'
assert all(f[k].startswith('team-e2e-'+k+'-') and f[k].endswith('@example.edu') for k in ('a','b')), 'Synthetic accounts required'
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
tokens=[]
for who in ('a','b'):
 v=ok('/auth/v1/token?grant_type=password',{'email':f[who],'password':f['password']})
 tokens.append(v['access_token'])
a_token,b_token=tokens
assert req('/rest/v1/game_spots')[0] in (401,403)
assert req('/rest/v1/rpc/begin_point_attack',{'spot_id':spot,'request_id':uid(),'latitude':0,'longitude':0,'accuracy_meters':0,'fix_at':datetime.datetime.now(datetime.timezone.utc).isoformat()},None)[0] in (401,403)
assert req('/rest/v1/game_spots?id=eq.'+spot,{'hp':1},a_token,'PATCH')[0] in (401,403)
assert req('/rest/v1/question_bank',None,a_token)[0]>=400
for extra in ({'latitude':1},{'accuracy_meters':16},{'fix_at':'2020-01-01T00:00:00Z'}):
 status,_=req('/rest/v1/rpc/begin_point_attack',{'spot_id':spot,'request_id':uid(),'latitude':0,'longitude':0,'accuracy_meters':0,'fix_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),**extra},a_token)
 assert status>=400
attack=begin(a_token)
assert 'correct_option_id' not in json.dumps(attack)
assert begin(a_token)['question']['instance_id']==attack['question']['instance_id']
assert req('/rest/v1/rpc/read_point_attack',{'attack_id':attack['id']},b_token)[0]>=400
seen=set();events=[]
for mode in ('miss','wrong','miss','wrong','correct'):
 old=attack;body=shot(a_token,old,mode);result=ok('/rest/v1/rpc/submit_point_kick',body,a_token)
 assert result['outcome']==mode,result
 attack=result['state'];seen.add(attack['question']['bank_id'])
 assert attack['question']['instance_id']!=old['question']['instance_id']
 assert attack['question']['bank_id']!=old['question']['bank_id']
 assert attack['point']['hp']==(75 if mode=='correct' else 100)
 assert begin(a_token)['question']['instance_id']==attack['question']['instance_id']
 assert ok('/rest/v1/rpc/submit_point_kick',body,a_token)==result
 assert req('/rest/v1/rpc/submit_point_kick',{**body,'command_id':uid()},a_token)[0]>=400
 events.append(mode)
# Two clients submitting the same question simultaneously cannot double damage.
body=shot(a_token,attack)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
 results=list(pool.map(lambda _:req('/rest/v1/rpc/submit_point_kick',{**body,'command_id':uid()},a_token),range(2)))
assert sum(s<300 for s,_ in results)==1,results
attack=ok('/rest/v1/rpc/read_point_attack',{'attack_id':attack['id']},a_token)
assert attack['point']['hp']==50
shared=ok('/rest/v1/game_spots?id=eq.'+spot,None,b_token)[0]
assert shared['hp']==50
# Preserve an active session for the emulator close/reopen and capture tests.
Path('output/team-e2e/live-rest-evidence.json').write_text(json.dumps({'events':events,'distinct_next_questions':len(seen),'race_successes':1,'shared_hp':50,'attack_id':attack['id'],'question_id':attack['question']['instance_id'],'sequence':attack['sequence']},indent=2))
print('PASS: live auth/RLS, GPS guards, hidden answers, random next questions, unlimited losses, replay/stale protection, concurrent kick and second-client shared HP.')
