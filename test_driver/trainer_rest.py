"""Live QA for profile isolation, avatar storage and idempotent progression."""
from pathlib import Path
exec(Path('test_driver/live_attack_rest.py').read_text().split('tokens={};users={}')[0])
from PIL import Image,ImageDraw
import io
out=Path('output/trainer-e2e');out.mkdir(parents=True,exist_ok=True)
sessions={k:ok('/auth/v1/token?grant_type=password',{'email':f[k],'password':f['password']}) for k in ('a','b')}
tokens={k:v['access_token'] for k,v in sessions.items()}
def trainer(k='a'):return ok('/rest/v1/rpc/read_trainer',{},tokens[k])
a=trainer(); assert a['progress']['xp']==0,'Fresh progression expected; do not reset existing records.'
assert len(a['levels'])==20 and len(a['ranks'])==5 and len(a['achievements'])==8
def save(profile,who='a',**extra):
 return req('/rest/v1/rpc/update_trainer_profile',{'trainer_username':'qa_explorer_'+f['run'][-8:],'trainer_name':'QA Campus Explorer','trainer_bio':'Testing a real saved trainer profile.','trainer_avatar':None,'expected_revision':profile['revision'],**extra},tokens[who])
status,p=save(a['profile']); assert status==200,(status,p)
assert save(a['profile'])[0]==409,'Stale update accepted'
b=trainer('b'); assert save(b['profile'],'b')[0]==409,'Duplicate username accepted'
assert save(p,trainer_username='bad name!')[0]==400
for table,keycol in [('player_profiles','id'),('player_progress','user_id')]:
 assert req('/rest/v1/'+table+'?'+keycol+'=eq.'+sessions['a']['user']['id'],{'xp':999999} if table=='player_progress' else {'display_name':'Overwrite'},tokens['b'],'PATCH')[0] in (400,403)
 assert ok('/rest/v1/'+table+'?'+keycol+'=eq.'+sessions['a']['user']['id'],token=tokens['b'])==[]
assert req('/rest/v1/rpc/read_trainer',{},None)[0] in (401,403)
assert req('/rest/v1/progression_settings?id=eq.true',{'correct_xp':999},tokens['a'],'PATCH')[0]==403
print('PASS: unique usernames, profile validation, stale revision conflict, account isolation and protected XP/config writes.',flush=True)

image=Image.new('RGB',(512,512),'#123d2b');draw=ImageDraw.Draw(image);draw.ellipse((90,70,420,400),fill='#efc467');draw.rectangle((70,350,440,400),fill='#e85c08')
buffer=io.BytesIO();image.save(buffer,format='JPEG');photo=buffer.getvalue();(out/'qa-avatar.jpg').write_bytes(photo)
path=sessions['a']['user']['id']+'/'+uid()+'.jpg'
def binary_upload(who,path,content=photo,mime='image/jpeg'):
 request=urllib.request.Request(base+'/storage/v1/object/trainer-avatars/'+path,data=content,headers={'apikey':key,'Authorization':'Bearer '+tokens[who],'Content-Type':mime},method='POST')
 try:
  with urllib.request.urlopen(request,timeout=30) as response:return response.status
 except urllib.error.HTTPError as e:return e.code
assert binary_upload('a',path)==200
assert binary_upload('b',sessions['a']['user']['id']+'/'+uid()+'.jpg')>=400
assert binary_upload('a',sessions['a']['user']['id']+'/'+uid()+'.html',b'<html>','text/html')>=400
status,p=save(p,trainer_avatar=path);assert status==200,(status,p)
assert save(b['profile'],'b',trainer_username='qa_other_'+f['run'][-8:],trainer_avatar=path)[0]==403
assert req('/storage/v1/object/sign/trainer-avatars/'+path,{'expiresIn':60},tokens['b'])[0]>=400
fresh=trainer();assert fresh['profile']['avatar_path']==path and fresh['profile']['display_name']=='QA Campus Explorer'
print('PASS: real JPEG upload/profile link persists; private avatar cross-account access and invalid MIME rejected.',flush=True)

def hit(a,mode='correct'):
 body=shot(tokens['a'],a,mode);result=ok('/rest/v1/rpc/submit_point_kick',body,tokens['a'])
 assert result['outcome']==mode,result
 xp=trainer()['progress']['xp']
 assert ok('/rest/v1/rpc/submit_point_kick',body,tokens['a'])==result
 assert trainer()['progress']['xp']==xp,'Receipt replay duplicated XP'
 return result['state']
for point in ('perfect','capture'):
 a=begin(tokens['a'],spot_id='qa-trainer-'+point+'-20261022')
 for _ in range(4):a=hit(a)
 assert a['status']==('captured' if point=='capture' else 'completed')
progress=trainer()['progress'];assert progress['xp']==400 and progress['perfect_attacks']==2 and progress['captures']==1,progress
a=begin(tokens['a'],spot_id='qa-trainer-mixed-20261022');a=hit(a);a=hit(a,'wrong');a=hit(a,'miss')
remaining=(dt(a['question']['due_at'])-dt(a['server_now'])).total_seconds()
print('Waiting for one real question timeout to verify zero timeout XP...',flush=True)
time.sleep(max(0,remaining)+.2)
a=ok('/rest/v1/rpc/read_point_attack',{'attack_id':a['id']},tokens['a'])
assert a['status']=='completed' and trainer()['progress']['xp']==425
a=begin(tokens['a'],spot_id='qa-trainer-early-20261022');a=hit(a)
assert a['status']=='captured' and a['correct_count']==1
fresh=trainer();progress=fresh['progress']
assert progress['xp']==550 and progress['correct_kicks']==10 and progress['captures']==2 and progress['perfect_attacks']==2 and progress['completed_attacks']==4,progress
earned={a['id'] for a in fresh['achievements'] if a['earned_at']}
assert {'first-kick','ten-correct','first-perfect','first-capture'}<=earned
assert trainer('b')['progress']['xp']==0
assert ok('/rest/v1/account_teams?user_id=eq.'+sessions['a']['user']['id'],token=tokens['a'])[0]['team_id']=='art_stuff'
(out/'rest-results.json').write_text(json.dumps({'progress':progress,'earned':sorted(earned),'profile':fresh['profile'],'checks':['duplicates','RLS','storage','unique username','stale revision','perfect','early capture','wrong','miss','timeout']},indent=2))
print('PASS: 550 exact XP; perfect/capture bonuses; wrong/miss/timeout zero; early capture not perfect; 4 milestones unlocked once; other account/team unchanged.',flush=True)
