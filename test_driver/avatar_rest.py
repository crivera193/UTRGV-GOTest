"""Live preset-only policy checks on the isolated QA account."""
from pathlib import Path
import base64
exec(Path('test_driver/live_attack_rest.py').read_text().split('tokens={};users={}')[0])
s=ok('/auth/v1/token?grant_type=password',{'email':f['a'],'password':f['password']});token=s['access_token']
before=ok('/rest/v1/rpc/read_trainer',{},token);p=before['profile']
assert len(before['avatars'])==6 and p['avatar_path'] is None
def save(avatar):return req('/rest/v1/rpc/update_trainer_profile',{'trainer_username':p['username'],'trainer_name':p['display_name'],'trainer_bio':p['bio'],'trainer_avatar':avatar,'expected_revision':p['revision']},token)
for invalid in ('https://example.com/photo.jpg',s['user']['id']+'/old.jpg','data:image/jpeg;base64,abc','not-approved',None):
 assert save(invalid)[0]==400,'Arbitrary photo source accepted'
assert req('/rest/v1/trainer_avatars',{'id':'unsafe','label':'User upload','design':'external','background':'#ffffff','accent':'#000000'},token)[0]==403
assert req('/rest/v1/player_profiles?id=eq.'+s['user']['id'],{'avatar_id':'cat'},token,'PATCH')[0]==403
photo=base64.b64decode('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAEDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwD3+iiigD//2Q==')
for upsert in (False,True):
 headers={'apikey':key,'Authorization':'Bearer '+token,'Content-Type':'image/jpeg'}
 if upsert:headers['x-upsert']='true'
 r=urllib.request.Request(base+'/storage/v1/object/trainer-avatars/'+s['user']['id']+'/'+uid()+'.jpg',data=photo,headers=headers,method='POST')
 try:
  with urllib.request.urlopen(r,timeout=20) as response:raise AssertionError('Custom upload accepted')
 except urllib.error.HTTPError as e:assert e.code>=400
old=ok('/rest/v1/player_profiles?id=eq.'+s['user']['id'],token=token)[0]['avatar_path']
if old:assert req('/storage/v1/object/sign/trainer-avatars/'+old,{'expiresIn':60},token)[0]>=400
status,p=save('cat');assert status==200,(status,p)
fresh=ok('/auth/v1/token?grant_type=password',{'email':f['a'],'password':f['password']})
after=ok('/rest/v1/rpc/read_trainer',{},fresh['access_token'])
assert after['profile']['avatar_id']=='cat' and after['profile']['avatar_path'] is None
assert after['progress']['xp']==before['progress']['xp']
assert ok('/rest/v1/account_teams?user_id=eq.'+s['user']['id'],token=token)[0]['team_id']=='art_stuff'
print('PASS: six approved presets; file paths, URLs, data URIs and unknown IDs rejected; direct upload/upsert/signing blocked; preset persists in fresh session with XP/team unchanged.')
