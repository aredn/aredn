#!/usr/bin/env python3
"""Run unmodified root/template logic, replacing device imports and absolute paths."""
import json, os, pathlib, re, subprocess, sys, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[3]
UCODE = os.environ.get('UCODE', 'ucode')

def run(request):
    with tempfile.TemporaryDirectory(prefix='aredn-web-') as temporary:
        temp = pathlib.Path(temporary)
        board = temp/'board.json'
        board.write_bytes(json.dumps({'model':{'id':'mikrotik,hap-ac3','name':'MikroTik hAP ac3'}}).encode()
                          if request.get('healthy') else b'\0'*1436)
        source = (ROOT/'files/app/root.ut').read_text()
        source = re.sub(r'import \* as (\w+) from "[^"]+";',
                        lambda m: f'const {m[1]} = fixture.{m[1]};', source)
        source = source.replace('"/app/partial/board-recovery.ut"',
                                json.dumps(str(ROOT/'files/app/partial/board-recovery.ut')))
        source += '\n{% global.handle_request(input.env); %}\n'
        template = temp/'root.ut'
        template.write_text(source)
        env = dict(PATH_INFO='/', REQUEST_METHOD='GET', CONTENT_TYPE='',
                   CONTENT_LENGTH='0', REMOTE_ADDR='192.0.2.2', headers={})
        env.update(request.get('env', {}))
        data = dict(board=str(board), template=str(template), env=env, body=request.get('body', ''),
                    missingShadow=request.get('missingShadow', False))
        inputs = temp/'input.json'
        inputs.write_text(json.dumps(data))
        process = subprocess.run([UCODE, *(['-L', os.environ['UCODE_FS_PATH']] if os.environ.get('UCODE_FS_PATH') else []), '-L', str(ROOT/'files/usr/share/ucode'),
                                  str(ROOT/'scripts/tests/board-data/web-fixture.uc'), str(inputs)],
                                 capture_output=True, text=True, check=True)
        return json.loads(process.stdout)

if __name__ == '__main__':
    try:
        print(json.dumps(run(json.load(sys.stdin))))
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stderr)
        sys.exit(error.returncode)
