"""Local-only browser fixture. No replacement compiler or extension packaging."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
import json

ROOT = Path(__file__).resolve().parent

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = self.path.split('?')[0]
        routes = {'/': ('extension-fixture.html', 'text/html'), '/fixture.js': ('fixture.js', 'text/javascript'), '/content.js': ('../extension/content.js', 'text/javascript')}
        if path not in routes:
            self.send_error(404); return
        name, mime = routes[path]
        data = (ROOT / name).read_bytes()
        self.send_response(200); self.send_header('Content-Type', mime); self.end_headers(); self.wfile.write(data)

    def do_POST(self):
        if self.path != '/review':
            self.send_error(404); return
        body = self.rfile.read(min(int(self.headers.get('Content-Length', 0)), 100000))
        req = Request('http://127.0.0.1:8000/api/extension/review', data=body, headers={'Content-Type': 'application/json', 'X-PromptZero-Client': 'extension-v1', 'Origin': 'chrome-extension://' + 'a' * 32})
        try:
            with urlopen(req, timeout=15) as response:
                code, data = response.status, response.read()
        except HTTPError as error:
            code, data = error.code, error.read()
        except URLError:
            code, data = 503, json.dumps({'detail': 'Start PromptZero with ./run.sh, then retry.'}).encode()
        self.send_response(code); self.send_header('Content-Type', 'application/json'); self.end_headers(); self.wfile.write(data)

if __name__ == '__main__':
    HTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
