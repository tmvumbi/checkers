#!/usr/bin/env python3
"""Live regression: creates two temporary guests and deletes only those guests.

Uses the app's anonymous API key and each new guest's own session. Exercises
the same Storage removal and account RPC as the app. Never prints tokens.
Run after migrations 0037 and 0038: python3 scripts/test_account_deletion.py
"""

import json
import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).resolve().parents[1]
BASE = os.environ.get('CHECKERS_SUPABASE_URL', 'https://api.dame.cd').rstrip('/')
KEY = Path(os.environ.get(
    'CHECKERS_ANON_KEY_FILE',
    str(Path.home() / '.config/checkers_supabase_anon_key'),
)).read_text().strip()


def request(method, path, *, token=None, data=None, image=None, prefer=None):
    args = ['curl', '-sS', '--max-time', '30', '-X', method,
            '-H', 'apikey: ' + KEY, '-w', '\n%{http_code}']
    if token:
        args += ['-H', 'Authorization: Bearer ' + token]
    if prefer:
        args += ['-H', 'Prefer: ' + prefer]
    if image:
        args += ['-H', 'Content-Type: image/png', '--data-binary', '@' + str(image)]
    elif data is not None:
        args += ['-H', 'Content-Type: application/json', '--data-binary', json.dumps(data)]
    result = subprocess.run(args + [BASE + path], capture_output=True, text=True)
    body, _, status = result.stdout.rpartition('\n')
    if result.returncode or not status.isdigit():
        raise RuntimeError('Transport failed for ' + path.split('?')[0])
    try:
        payload = json.loads(body) if body else None
    except ValueError:
        payload = None
    return int(status), payload


def ok(method, path, **kwargs):
    status, data = request(method, path, **kwargs)
    if not 200 <= status < 300:
        code = data.get('code', data.get('error')) if isinstance(data, dict) else None
        raise RuntimeError(f'{method} {path.split("?")[0]}: HTTP {status}, code={code}')
    return data


def run_case(with_avatar):
    label = 'with avatar' if with_avatar else 'without avatar'
    session = ok('POST', '/auth/v1/signup', data={})
    uid, token = session['user']['id'], session['access_token']
    path = uid + '/avatar.jpg'  # Same object name the app uses.
    deleted = False
    try:
        ok('POST', '/rest/v1/profiles', token=token,
           prefer='resolution=merge-duplicates',
           data={'id': uid, 'nickname': 'DeletionTest', 'is_anonymous': True})
        if with_avatar:
            ok('POST', '/storage/v1/object/avatars/' + path, token=token,
               image=ROOT / 'assets/icons/app_logo.png')
            status, error = request('POST', '/rest/v1/rpc/delete_account', token=token, data={})
            assert status == 400 and error.get('message') == 'avatar_cleanup_required', \
                'RPC must refuse deletion while avatar files remain'
            assert ok('GET', '/auth/v1/user', token=token)['id'] == uid
            print('PASS: account survives attempted deletion before avatar cleanup')

        # Removing a missing avatar and repeating successful cleanup must both
        # work: those are guest deletion and retry-after-RPC-failure scenarios.
        for _ in range(2):
            ok('DELETE', '/storage/v1/object/avatars', token=token, data={'prefixes': [path]})
        remaining = ok('POST', '/storage/v1/object/list/avatars', token=token,
                       data={'prefix': uid, 'limit': 100})
        assert remaining == [], 'Avatar must be gone before deleting the account'
        ok('POST', '/rest/v1/rpc/delete_account', token=token, data={})
        deleted = True
        status, _ = request('GET', '/auth/v1/user', token=token)
        assert status in (401, 403, 404), 'Deleted account must no longer validate'
        rows = ok('GET', '/rest/v1/profiles?id=eq.' + uid + '&select=id', token=token)
        assert rows == [], 'Profile must be removed by account deletion'
        print(f'PASS: deletion {label}; file, auth user, and profile removed')
    finally:
        if not deleted:
            # Cleanup is restricted to the account created by this test.
            ok('DELETE', '/storage/v1/object/avatars', token=token, data={'prefixes': [path]})
            ok('POST', '/rest/v1/rpc/delete_account', token=token, data={})


if __name__ == '__main__':
    run_case(False)
    run_case(True)
    print('All live account-deletion checks passed.')
