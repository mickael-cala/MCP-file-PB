#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mock minimal de l'API GitHub (pour les tests d'integration du serveur githubMCP).

Lance un serveur HTTP local qui imite les endpoints utilises :
    GET  /repos/{o}/{r}                 -> 200 (ou 404/401/403/JSON invalide
                                           selon le nom du depot)
    GET  /repos/{o}/{r}/issues          -> liste (echo des parametres)
    GET  /repos/{o}/{r}/issues/{n}      -> issue
    POST /repos/{o}/{r}/issues          -> 201 (422 si title == "invalid")
    GET  /repos/{o}/{r}/pulls           -> liste
    GET  /repos/{o}/{r}/pulls/{n}       -> PR
    POST /repos/{o}/{r}/pulls           -> 201
    GET  /repos/{o}/{r}/commits         -> liste (echo de sha)
    GET  /search/code                   -> 200 (403 si q contient "ratelimit")
    GET  /search/repositories           -> 200

Usage :
    server = MockGitHub()
    base = server.start()   # ex. http://127.0.0.1:PORT
    ...
    server.stop()
"""

import json
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs, unquote


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # silencieux

    def _send(self, code, payload):
        body = payload if isinstance(payload, str) else json.dumps(payload)
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _echo(self):
        return {
            "path": self.path,
            "query": {k: v[0] for k, v in parse_qs(urlparse(self.path).query).items()},
            "authorization": self.headers.get("Authorization", ""),
            "api_version": self.headers.get("X-GitHub-Api-Version", ""),
        }

    def do_GET(self):
        path = urlparse(self.path).path
        parts = [p for p in path.split("/") if p]

        # /search/...
        if parts[:1] == ["search"]:
            q = parse_qs(urlparse(self.path).query).get("q", [""])[0]
            if parts[1:] == ["code"]:
                if "ratelimit" in q.lower():
                    self._send(403, {"message": "API rate limit exceeded for user"})
                else:
                    self._send(200, {"total_count": 1, "items": [
                        {"name": "example.py", "path": "src/example.py", "echo": self._echo()}
                    ]})
                return
            if parts[1:] == ["repositories"]:
                self._send(200, {"total_count": 1, "items": [
                    {"full_name": "mock/repo", "echo": self._echo()}
                ]})
                return
            self._send(404, {"message": "Not Found"})
            return

        # /repos/{o}/{r}[/...]
        if parts[:1] == ["repos"] and len(parts) >= 3:
            repo = unquote(parts[2])
            if repo == "notfound":
                self._send(404, {"message": "Not Found"})
                return
            if repo == "unauth":
                self._send(401, {"message": "Bad credentials"})
                return
            if repo == "ratelimit":
                self._send(403, {"message": "API rate limit exceeded"})
                return
            if repo == "badjson":
                self._send(200, "ceci n'est pas du JSON")
                return

            rest = parts[3:]
            if not rest:
                self._send(200, {"full_name": f"{unquote(parts[1])}/{repo}", "echo": self._echo()})
                return
            if rest == ["issues"] and self.command == "GET":
                q = parse_qs(urlparse(self.path).query)
                per_page = int(q.get("per_page", ["30"])[0])
                items = [{"number": i + 1, "title": f"issue {i + 1}", "state": q.get("state", ["open"])[0]}
                         for i in range(per_page)]
                self._send(200, {"items": items, "count": len(items), "echo": self._echo()})
                return
            if len(rest) == 2 and rest[0] == "issues":
                self._send(200, {"number": int(rest[1]), "title": "issue detail", "echo": self._echo()})
                return
            if rest == ["pulls"] and self.command == "GET":
                q = parse_qs(urlparse(self.path).query)
                per_page = int(q.get("per_page", ["30"])[0])
                items = [{"number": i + 1, "title": f"pr {i + 1}"} for i in range(per_page)]
                self._send(200, {"items": items, "count": len(items), "echo": self._echo()})
                return
            if len(rest) == 2 and rest[0] == "pulls":
                self._send(200, {"number": int(rest[1]), "title": "pr detail", "echo": self._echo()})
                return
            if rest == ["commits"]:
                q = parse_qs(urlparse(self.path).query)
                self._send(200, {"commits": [{"sha": "abc123", "message": "test"}],
                                 "sha": q.get("sha", [""])[0], "echo": self._echo()})
                return
            self._send(404, {"message": "Not Found"})
            return

        self._send(404, {"message": "Not Found"})

    def do_POST(self):
        path = urlparse(self.path).path
        parts = [p for p in path.split("/") if p]
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length).decode("utf-8") if length else ""
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            self._send(400, {"message": "invalid json"})
            return

        if parts[:1] == ["repos"] and len(parts) >= 4:
            rest = parts[3:]
            if rest == ["issues"]:
                if payload.get("title") == "invalid":
                    self._send(422, {"message": "Validation Failed"})
                else:
                    self._send(201, {"number": 1, "title": payload.get("title"),
                                     "authorization": self.headers.get("Authorization", "")})
                return
            if rest == ["pulls"]:
                self._send(201, {"number": 2, "title": payload.get("title"),
                                 "head": payload.get("head"), "base": payload.get("base"),
                                 "authorization": self.headers.get("Authorization", "")})
                return
        self._send(404, {"message": "Not Found"})


class MockGitHub:
    def __init__(self):
        self.httpd = HTTPServer(("127.0.0.1", 0), _Handler)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)

    def start(self):
        self.thread.start()
        host, port = self.httpd.server_address
        return f"http://{host}:{port}"

    def stop(self):
        self.httpd.shutdown()
        self.httpd.server_close()
