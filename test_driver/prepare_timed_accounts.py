"""Create/reuse only two extra synthetic accounts for the live four-player checks."""
import json
import re
import urllib.error
import urllib.request
from pathlib import Path

cfg = json.loads(Path('.env.app.local.json').read_text(encoding='utf-8-sig'))
fixture_path = Path('output/team-e2e/fixture.json')
fixture = json.loads(fixture_path.read_text(encoding='utf-8-sig'))
assert cfg['SUPABASE_URL'] == 'https://oipidltfvzodpiumdsaq.supabase.co'
assert re.fullmatch(r'[a-z0-9_]+', fixture['run'])
key = cfg.get('SUPABASE_PUBLISHABLE_KEY') or cfg.get('SUPABASE_ANON_KEY')

def call(path, payload, token=None):
    headers = {'apikey': key, 'Content-Type': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    request = urllib.request.Request(cfg['SUPABASE_URL'] + path,
                                    data=json.dumps(payload).encode(), headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=25) as response:
            return response.status, json.load(response)
    except urllib.error.HTTPError as error:
        return error.code, json.load(error)

for who in ('c', 'd'):
    email = f"team-e2e-{who}-{fixture['run']}@example.edu"
    credentials = {'email': email, 'password': fixture['password']}
    status, result = call('/auth/v1/token?grant_type=password', credentials)
    if status == 400 and result.get('code') == 'invalid_credentials':
        status, result = call('/auth/v1/signup', credentials)
    assert status < 300, 'Synthetic account setup failed'
    status, _ = call('/rest/v1/rpc/choose_team', {'requested_team': 'art_stuff'},
                     result['access_token'])
    assert status < 300, 'Synthetic permanent membership failed'
    fixture[who] = email
fixture_path.write_text(json.dumps(fixture, indent=2), encoding='utf-8')
print('Synthetic C/D accounts and permanent memberships ready; credentials remain ignored.')
