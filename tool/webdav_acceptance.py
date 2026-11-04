"""Run synthetic repository acceptance against an ephemeral WsgiDAV HTTPS server.

Install tool/webdav-requirements.txt in a virtualenv, then run this script with
that Python. --dart may select the workspace SDK. All storage, sockets, clients
and server threads belong to this foreground invocation and are cleaned up.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
import threading

from cheroot.ssl.builtin import BuiltinSSLAdapter
from cheroot.wsgi import Server
from wsgidav.wsgidav_app import WsgiDAVApp


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dart', default='dart')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='foliarc-dav-acceptance-') as data:
        for name in ('source space & 中文', 'destination'):
            (Path(data) / name).mkdir()
        app = WsgiDAVApp({
            'provider_mapping': {'/': data},
            'simple_dc': {'user_mapping': {'*': {'test': {'password': 'only'}}}},
            'http_authenticator': {'accept_basic': True, 'accept_digest': False,
                                   'default_to_digest': False},
            'verbose': 0,
        })
        server = Server(('127.0.0.1', 0), app, numthreads=4)
        fixtures = ROOT / 'packages/mm_data/test/fixtures/dav_tls'
        server.ssl_adapter = BuiltinSSLAdapter(
            str(fixtures / 'certificate.pem'), str(fixtures / 'test-only-key.pem'))
        thread = None
        try:
            server.prepare()  # Binds an ephemeral loopback port before launching Dart.
            thread = threading.Thread(target=server.serve, name='test-webdav')
            thread.start()
            env = dict(os.environ, FOLIARC_TEST_DAV_URL=f'https://127.0.0.1:{server.bind_addr[1]}/')
            subprocess.run([args.dart, 'test', 'test/webdav_service_test.dart',
                            '--reporter', 'expanded'], cwd=ROOT / 'packages/mm_data',
                           env=env, check=True, timeout=180)
        finally:
            server.stop()
            if thread:
                thread.join(timeout=10)
                if thread.is_alive():
                    raise RuntimeError('WebDAV acceptance server failed to stop')


if __name__ == '__main__':
    main()
