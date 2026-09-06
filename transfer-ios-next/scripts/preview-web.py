"""Loopback-only UI fixture. This is NOT the iPhone server or an integration test."""
import json
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'MuseTransfer' / 'WebAssets'

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def json_response(self, value):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == '/web/info':
            return self.json_response({'alias': 'iPhone', 'version': 'UI 测试'})
        if self.path == '/web/uploads' or self.path.startswith('/web/files'):
            return self.json_response([])
        return super().do_GET()

    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        if self.path == '/web/session':
            return self.json_response({})
        self.send_error(501)

if __name__ == '__main__':
    ThreadingHTTPServer(('127.0.0.1', 8766), Handler).serve_forever()
