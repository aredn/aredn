#!/usr/bin/env python3
"""Native storage faults and patched OpenWrt consumers, isolated in temporary paths.

OPENWRT_TREE is a git checkout containing the pinned v25.12.5 commit. Only
`git show` reads it; this runner applies patch 764 to a temporary fixture.
UCODE_FS_PATH must contain fs.so built with patch 763 (file.sync/dir.sync).
"""
import fcntl
import json
import os
import pathlib
import re
import shlex
import subprocess
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OPENWRT = pathlib.Path(os.environ['OPENWRT_TREE'])
REV = 'f0a60eee2fe051741c643ea6118718aae1ef17fb'
UCODE = [os.environ.get('UCODE', 'ucode'), '-L', os.environ['UCODE_FS_PATH'],
         '-L', str(ROOT/'files/usr/share/ucode')]
GOOD = {'model': {'id': 'mikrotik,hap-ac3', 'name': 'MikroTik hAP ac3'},
        'network': {}, 'wlan': {}}
NEW = {**GOOD, 'marker': 'new'}
results = []


def check(name, ok):
    results.append({'name': name, 'pass': bool(ok)})
    if not ok:
        raise AssertionError(name)


def run(args, *, data=None, fault=None, env=None):
    merged = dict(os.environ, **(env or {}))
    if fault:
        merged.update(LD_PRELOAD=str(preload), BOARD_TEST_FAULT=fault)
    return subprocess.run(args, input=data, capture_output=True, text=True,
                          env=merged, timeout=20)


def uc(source, *args, fault=None):
    script.write_text(source)
    return run([*UCODE, str(script), *map(str, args)], fault=fault)


with tempfile.TemporaryDirectory(prefix='aredn-board-writers-') as temporary:
    temp = pathlib.Path(temporary)
    script = temp/'test.uc'
    preload = temp/'faults.so'
    subprocess.run(['cc', '-shared', '-fPIC', '-Wall', '-Wextra', '-Werror',
                    '-o', str(preload), str(HERE/'faults.c'), '-ldl'], check=True)
    dest = temp/'board.json'
    update = '''import * as board from "aredn.board";
const lock=board.acquire(ARGV[0]);
if (!lock) { print('{"status":"locked"}'); exit(1); }
printf("%J",board.write(ARGV[0],json(ARGV[1])));
lock.close();'''
    for name, fault, status, installed in [
        ('durable_replace', None, 'written', True),
        ('retry_interrupted_fsync', 'interrupt-once', 'written', True),
        ('short_write_enospc', 'short-write', 'failed', False),
        ('close_failure', 'close', 'failed', False),
        ('file_sync_failure', 'file-sync', 'failed', False),
        ('rename_failure', 'rename', 'failed', False),
        ('directory_sync_failure', 'dir-sync', 'failed', True),
    ]:
        original = json.dumps(GOOD)
        dest.write_text(original)
        p = uc(update, dest, json.dumps(NEW), fault=fault)
        r = json.loads(p.stdout)
        check(name+'_result', p.returncode == 0 and r['status'] == status and
              r['installed'] == installed)
        check(name+'_bytes', json.loads(dest.read_text()) == NEW if installed
              else dest.read_text() == original)
        check(name+'_cleanup', not list(temp.glob('.board-write-*')))
    dest.write_text(json.dumps(GOOD))
    p = uc(update, dest, json.dumps(GOOD), fault='file-sync')
    check('unchanged_avoids_storage_write', json.loads(p.stdout)['status'] == 'unchanged')
    p = uc(update, dest, '{}')
    check('invalid_update_preserves_original', json.loads(p.stdout)['status'] == 'failed'
          and json.loads(dest.read_text()) == GOOD)
    with open(str(dest)+'.lock', 'w') as held:
        fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
        p = uc(update, dest, json.dumps(NEW))
        check('separate_process_lock_contention', p.returncode == 1 and
              json.loads(dest.read_text()) == GOOD)
    p = uc(update, dest, json.dumps(NEW), fault='exit-before-rename')
    check('process_exit_before_rename_preserves_original', p.returncode == 99 and
          json.loads(dest.read_text()) == GOOD)
    # This is a process interruption, not a simulated storage-controller power cut.
    p = uc(update, dest, json.dumps(NEW))
    check('retry_after_interruption', json.loads(p.stdout)['status'] == 'written' and
          json.loads(dest.read_text()) == NEW)
    p = uc('''import * as fs from "fs";
let f=fs.open(ARGV[0],"w"); f.write("data");
let a=f.sync(); f.close(); let b=f.sync();
let d=fs.opendir(ARGV[1]); let c=d.sync(); d.close(); let e=d.sync();
printf("%J",[a,b,c,e]);''', temp/'sync-test', temp)
    check('native_sync_open_and_closed_handles', p.returncode == 0 and
          json.loads(p.stdout) == [True, None, True, None])

    cli = [*UCODE, str(ROOT/'files/usr/local/bin/aredn-board-write')]
    dest.write_bytes(b'\0'*1436)
    p = run([*cli, 'stdin', str(dest)], data=json.dumps(GOOD))
    check('cli_stdin_replaces_zero_filled', p.returncode == 0 and json.loads(dest.read_text()) == GOOD)
    for name, payload in [('bad_json', '{'), ('oversized', ' '*1048577)]:
        p = run([*cli, 'stdin', str(dest)], data=payload)
        check('cli_rejects_'+name, p.returncode == 1 and json.loads(dest.read_text()) == GOOD)
    p = run([*cli, 'install-if-invalid', str(dest)])
    check('cli_requires_source_argument', p.returncode == 1)
    source = temp/'candidate.json'
    source.write_text(json.dumps(NEW))
    p = run([*cli, 'install-if-invalid', str(dest), str(source)])
    check('install_preserves_concurrently_valid_destination', p.returncode == 0 and
          json.loads(dest.read_text()) == GOOD)

    # Apply the actual OpenWrt patch to exact-version sources, not reimplemented logic.
    patch = ROOT/'patches/764-durable-board-data.patch'
    paths = re.findall(r'^--- a/(.+)$', patch.read_text(), re.M)
    tree = temp/'openwrt'
    for name in paths:
        path = tree/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(subprocess.check_output(['git', '-C', str(OPENWRT), 'show', f'{REV}:{name}']))
    for name in ['763-ucode-fsync.patch', '764-durable-board-data.patch']:
        p = subprocess.run(['patch', '-p1', '--batch', '--fuzz=0', '-i', str(ROOT/'patches'/name)], cwd=tree,
                           capture_output=True, text=True)
        check('openwrt_'+name+'_exact_version', p.returncode == 0 and 'offset' not in p.stdout)

    # Replace only paths and external data producers. Keep full detector and flush logic.
    wrapper = temp/'aredn-board-write'
    wrapper.write_text('#!/bin/sh\nexec '+shlex.join(cli)+' "$@"\n')
    wrapper.chmod(0o700)
    board_dir = temp/'board.d'
    board_dir.mkdir()
    generator = board_dir/'01-synthetic'
    flush_file = temp/'flush.sh'
    shared = (tree/'package/base-files/files/lib/functions/uci-defaults.sh').read_text()
    flush = shared[shared.index('board_config_flush()'):]
    flush_file.write_text(flush.replace('/usr/local/bin/aredn-board-write', str(wrapper)))
    generator.write_text('. '+shlex.quote(str(flush_file))+'\n'
                         'json_dump() { printf \'%s\\n\' "$BOARD_TEST_JSON"; return "${BOARD_TEST_DUMP_STATUS:-0}"; }\n'
                         'board_config_flush\nexit 0\n')
    detector = temp/'board_detect'
    original_detector = subprocess.check_output(['git', '-C', str(OPENWRT), 'show',
        f'{REV}:package/base-files/files/bin/board_detect'], text=True)
    def detector_paths(text):
        return text.replace('/etc/board.d', str(board_dir)).replace('/usr/local/bin/aredn-board-write', str(wrapper))
    detector.write_text(detector_paths((tree/'package/base-files/files/bin/board_detect').read_text()))
    detector.chmod(0o700)
    control = temp/'board_detect-original'
    control.write_text(detector_paths(original_detector))
    dest.write_bytes(b'\0'*1436)
    p = run(['sh', str(control), str(dest)], env={'BOARD_TEST_JSON': json.dumps(GOOD)})
    check('original_detector_retains_nonempty_corruption', p.returncode != 0 and dest.read_bytes() == b'\0'*1436)
    p = run(['sh', str(detector), str(dest)], env={'BOARD_TEST_JSON': json.dumps(GOOD)})
    check('patched_detector_recovers_nonempty_corruption', p.returncode == 0 and json.loads(dest.read_text()) == GOOD)
    p = run(['sh', str(detector), str(dest)], env={'BOARD_TEST_JSON': '{}'}, fault='file-sync')
    check('healthy_detector_does_not_generate', p.returncode == 0 and json.loads(dest.read_text()) == GOOD)
    for name, payload, dump_status, fault in [
        ('invalid_json', '{}', '0', None),
        ('producer_failed_after_output', json.dumps(GOOD), '1', None),
        ('storage_failure', json.dumps(GOOD), '0', 'file-sync'),
    ]:
        dest.write_bytes(b'\0'*1436)
        p = run(['sh', str(detector), str(dest)], env={'BOARD_TEST_JSON': payload,
                'BOARD_TEST_DUMP_STATUS': dump_status}, fault=fault)
        check('detector_'+name+'_preserves_original', p.returncode != 0 and dest.read_bytes() == b'\0'*1436)
        check('detector_'+name+'_cleanup', not list(temp.glob('.board-detect-*')))

    # Execute the entire Wi-Fi writer with a deterministic radio/sysfs provider.
    wifi = (tree/'package/network/config/wifi-scripts/files/usr/share/hostap/wifi-detect.uc').read_text()
    provider = '''import * as fs from "fs";
const readfile=fs.readfile;
const realpath=path=>"/sys/devices/platform/fixture-radio";
const glob=path=>[];
const basename=fs.basename;
'''
    wifi = re.sub(r'import \{[^\n]+\} from "fs";', provider, wifi)
    wifi = wifi.replace('let nl = require("nl80211");', '''const nl={const:{},request:()=>json(ARGV[0])};''')
    wifi = wifi.replace('"/etc/board.json"', json.dumps(str(dest)))
    wifi_file = temp/'wifi-detect.uc'
    wifi_file.write_text(wifi)
    radio = [{'wiphy_name': 'phy0', 'wiphy_antenna_avail_rx': 3,
              'wiphy_antenna_avail_tx': 3, 'radios': [],
              'wiphy_bands': [{'freqs': [{'freq': 2412}], 'ht_capa': 2}]}]
    dest.write_text(json.dumps(GOOD))
    p = run([*UCODE, str(wifi_file), json.dumps(radio)])
    check('wifi_adds_radio_metadata', p.returncode == 0 and
          json.loads(dest.read_text())['wlan']['phy0']['info']['bands']['2G']['default_channel'] == 1)
    previous = dest.read_text()
    p = run([*UCODE, str(wifi_file), 'null'])
    check('wifi_netlink_failure_keeps_previous_metadata', p.returncode == 1 and dest.read_text() == previous)
    for fault in ['file-sync', 'rename']:
        p = run([*UCODE, str(wifi_file), '[]'], fault=fault)
        check('wifi_'+fault+'_preserves_original', p.returncode == 1 and dest.read_text() == previous)
    with open(str(dest)+'.lock', 'w') as held:
        fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
        p = run([*UCODE, str(wifi_file), '[]'])
        check('wifi_holds_transaction_lock', p.returncode == 1 and dest.read_text() == previous)
    dest.write_bytes(b'\0'*1436)
    p = run([*UCODE, str(wifi_file), json.dumps(radio)])
    check('wifi_invalid_input_is_not_overwritten', p.returncode == 1 and dest.read_bytes() == b'\0'*1436)

    # Preinit consumer: real install path, with detection/configuration effects stubbed.
    preinit = (tree/'package/base-files/files/lib/preinit/82_config_generate').read_text()
    first = temp/'firstboot.json'
    calls = temp/'config-generate-calls'
    preinit = preinit.replace('/etc/board.json', str(first)).replace('/tmp/board.json', str(source))
    preinit = preinit.replace('/usr/local/bin/aredn-board-write', str(wrapper))
    preinit = preinit.replace('/tmp/.uci', str(temp/'uci'))
    preinit = preinit.replace('/etc/uci-defaults/30_uboot-envtools', str(temp/'absent-uboot'))
    preinit = preinit.replace('/bin/board_detect', 'detect_fixture').replace('/bin/config_generate', 'config_fixture')
    preinit_file = temp/'preinit.sh'
    preinit_file.write_text('boot_hook_add() { :; }\ndetect_fixture() { return 0; }\n'
                           'config_fixture() { echo called >> '+shlex.quote(str(calls))+'; }\n'+preinit+'\ndo_config_generate\n')
    source.write_text(json.dumps(GOOD))
    p = run(['sh', str(preinit_file)])
    check('firstboot_durable_install_then_generate', p.returncode == 0 and
          json.loads(first.read_text()) == GOOD and calls.read_text() == 'called\n')
    first.unlink(); calls.unlink()
    p = run(['sh', str(preinit_file)], fault='file-sync')
    check('firstboot_failure_skips_configuration', p.returncode != 0 and not first.exists() and not calls.exists())

    # Execute the real caller functions; no wireless UCI generation/retry after failure.
    wifi_shell = (tree/'package/network/config/wifi-scripts/files/sbin/wifi').read_text()
    wifi_config = wifi_shell[wifi_shell.index('wifi_config() {'):]
    wifi_config = wifi_config[:wifi_config.index('\n}\n')+3]
    caller = temp/'wifi-caller.sh'
    caller.write_text('ucode() { return 7; }\n'
                      'touch() { echo touched >> '+shlex.quote(str(calls))+'; }\n'+
                      wifi_config+'\nwifi_config\n')
    p = run(['sh', str(caller)])
    check('wifi_caller_propagates_failure', p.returncode == 7 and not calls.exists())
    hotplug = (tree/'package/network/config/wifi-scripts/files/etc/hotplug.d/ieee80211/10-wifi-detect').read_text()
    hotplug = hotplug.replace('/etc/board.json', str(dest)).replace('/sbin/wifi', 'wifi_fixture')
    caller.write_text('wifi_fixture() { return 7; }\n'
                      'ubus() { echo retry >> '+shlex.quote(str(calls))+'; }\n'+hotplug)
    p = run(['sh', str(caller)], env={'ACTION': 'add'})
    check('hotplug_does_not_retry_failed_metadata', p.returncode == 7 and not calls.exists())

print(json.dumps({'passed': sum(r['pass'] for r in results), 'total': len(results),
                  'results': results}, indent=2))
