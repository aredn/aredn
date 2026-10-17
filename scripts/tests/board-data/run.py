#!/usr/bin/env python3
"""Native regression checks; only task-owned temporary files are modified."""
import base64, hashlib, importlib.util, json, os, pathlib, subprocess, tempfile, urllib.parse
ROOT = pathlib.Path(__file__).resolve().parents[3]
HERE = pathlib.Path(__file__).resolve().parent
UCODE = os.environ.get('UCODE', 'ucode')
spec=importlib.util.spec_from_file_location('fixture', HERE/'web-fixture.py')
fixture=importlib.util.module_from_spec(spec); spec.loader.exec_module(fixture)
results=[]
def check(name, condition):
    results.append({'name':name,'pass':bool(condition)})
    if not condition: raise AssertionError(name)
with tempfile.TemporaryDirectory(prefix='aredn-board-native-') as directory:
    p=subprocess.run([UCODE,*(['-L',os.environ['UCODE_FS_PATH']] if os.environ.get('UCODE_FS_PATH') else []),'-L',str(ROOT/'files/usr/share/ucode'),str(HERE/'native.uc'),directory],capture_output=True,text=True)
    if p.returncode: raise RuntimeError(p.stderr)
    results.extend(json.loads(p.stdout))
check('reported_fixture_bytes_match',hashlib.sha256(b'\0'*1436).hexdigest()=='c3bf51869a4db89a6a6c3d459827243126e1b05a8235b11a29380c8eb692679d')
shadow='root:$1$fixture$accepted:0:0:0:0:0:0'
cookie='authV1='+base64.b64encode(shadow.encode()).decode()
for name,request,admin in [
    ('anonymous',{},False),
    ('invalid_cookie',{'env':{'headers':{'cookie':'authV1=invalid'}}},False),
    ('unavailable_password_database',{'missingShadow':True,'env':{'headers':{'cookie':'authV1=invalid'}}},False),
    ('authenticated',{'env':{'headers':{'cookie':cookie}}},True),
    ('anonymous_config_put',{'env':{'REQUEST_METHOD':'PUT','PATH_INFO':'/status/e/network'}},False),
    ('authenticated_config_put',{'env':{'REQUEST_METHOD':'PUT','PATH_INFO':'/status/e/network','headers':{'cookie':cookie}}},True),
    ('oversized_login',{'env':{'REQUEST_METHOD':'POST','PATH_INFO':'/board-recovery','CONTENT_TYPE':'application/x-www-form-urlencoded','CONTENT_LENGTH':'4097'}},False),
]:
    r=fixture.run(request)
    check(name+'_503',r['response'].startswith('Status: 503'))
    check(name+'_auth_boundary',('id="board-error"' in r['response'])==admin)
    check(name+'_no_radio_or_configuration',r['calls']['radio']==0 and r['calls']['configuration']==0)
    check(name+'_no_body_read',r['calls']['recv']==0)
for password,accepted in [('wrong',False),('correct password+',True)]:
    body=urllib.parse.urlencode({'password':password})
    r=fixture.run({'body':body,'env':{'REQUEST_METHOD':'POST','PATH_INFO':'/board-recovery','CONTENT_TYPE':'application/x-www-form-urlencoded','CONTENT_LENGTH':str(len(body))}})
    check('login_'+('accepted' if accepted else 'rejected'),('id="board-error"' in r['response'])==accepted)
    check('login_cookie_'+str(accepted),('Set-Cookie:' in r['response'])==accepted)
    check('login_no_configuration_'+str(accepted),r['calls']['configuration']==0)
r=fixture.run({'healthy':True,'env':{'PATH_INFO':'/status'}})
check('healthy_uses_normal_dispatch',r['calls']['radio']==1 and 'Board information unavailable' not in r['response'])
assert all(r['pass'] for r in results)
print(json.dumps({'passed':len(results),'total':len(results),'results':results},indent=2))
