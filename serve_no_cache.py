"""정적 빌드(build/web)를 캐시 없이 서빙하는 개발용 서버.
브라우저가 main.dart.js 등을 캐싱해서 새로고침해도 옛날 버전이 보이는 문제를 막기 위함.
사용법: python serve_no_cache.py [포트, 기본 8386]
"""
import http.server
import functools
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8386


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


handler = functools.partial(NoCacheHandler, directory="build/web")
with http.server.ThreadingHTTPServer(("", PORT), handler) as httpd:
    print(f"Serving build/web on http://localhost:{PORT} (no-cache headers on every response)")
    httpd.serve_forever()
