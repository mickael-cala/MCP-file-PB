#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Tests fonctionnels du serveur MCP fileMCP (protocole JSON-RPC 2.0 sur stdio).

Lance le serveur compile avec MCP_ROOT pointant vers un repertoire temporaire,
puis exerce les outils MCP un par un.

Usage :
    python tests/test_mcp.py

Le binaire est cherche dans l'ordre :
    1. variable d'environnement FILEMCP_BIN
    2. build/fileMCP(.exe)
    3. src/fileMCP(.exe)
"""

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT_SECRET = "test-secret-123"
TIMEOUT = 10  # secondes

passed = 0
failed = 0


def check(name, condition, detail=""):
    global passed, failed
    if condition:
        passed += 1
        print(f"  [OK]   {name}")
    else:
        failed += 1
        print(f"  [FAIL] {name}  {detail}")


def find_binary():
    if os.environ.get("FILEMCP_BIN"):
        return Path(os.environ["FILEMCP_BIN"])
    exe = ".exe" if os.name == "nt" else ""
    for candidate in (f"build/fileMCP{exe}", f"src/fileMCP{exe}"):
        p = Path(__file__).resolve().parent.parent / candidate
        if p.exists():
            return p
    return None


class McpClient:
    """Client JSON-RPC minimal : une ligne JSON par requete/reponse."""

    def __init__(self, binary, root):
        env = os.environ.copy()
        env["MCP_ROOT"] = str(root)
        env["MCP_ROOT_SECRET"] = ROOT_SECRET
        self.proc = subprocess.Popen(
            [str(binary)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env=env,
            text=True,
            encoding="utf-8",
        )
        self._next_id = 0

    def call(self, method, params=None):
        self._next_id += 1
        req = {"jsonrpc": "2.0", "id": self._next_id, "method": method}
        if params is not None:
            req["params"] = params
        self.proc.stdin.write(json.dumps(req) + "\n")
        self.proc.stdin.flush()
        deadline = time.time() + TIMEOUT
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if not line:
                break
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except json.JSONDecodeError:
                continue
            if msg.get("id") == self._next_id:
                return msg
        raise TimeoutError(f"Pas de reponse pour {method} (id={self._next_id})")

    def tool(self, name, args):
        """Appelle tools/call et retourne (isError, texte du premier contenu)."""
        resp = self.call("tools/call", {"name": name, "arguments": args})
        result = resp.get("result") or {}
        content = result.get("content") or []
        text = content[0].get("text", "") if content else ""
        return bool(result.get("isError")), text

    def close(self):
        if self.proc.stdin:
            self.proc.stdin.close()
        try:
            self.proc.wait(timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()


def main():
    binary = find_binary()
    if binary is None:
        print("Binaire introuvable. Compilez d'abord avec build.bat / build.sh,")
        print("ou definissez FILEMCP_BIN.")
        sys.exit(1)

    print(f"Binaire teste : {binary}")

    with tempfile.TemporaryDirectory(prefix="filemcp-test-") as tmp:
        root = Path(tmp)
        client = McpClient(binary, root)
        try:
            run_tests(client, root)
        finally:
            client.close()

    print(f"\n{passed} reussis, {failed} echoues")
    sys.exit(0 if failed == 0 else 1)


def run_tests(client, root):
    print("\n-- tools/list --")
    resp = client.call("tools/list")
    tools = (resp.get("result") or {}).get("tools") or []
    names = {t.get("name") for t in tools}
    expected = {
        "list_files", "read_file", "read_file_lines", "write_file",
        "create_directory", "delete_file", "move_file", "get_file_info",
        "search_files", "change_root",
    }
    check("tools/list retourne 10 outils", len(tools) == 10, f"obtenu: {len(tools)}")
    check("catalogue conforme", names == expected, f"diff: {names ^ expected}")

    print("\n-- write_file / read_file --")
    err, text = client.tool("write_file", {"path": "hello.txt", "content": "ligne 1\nligne 2\n"})
    check("write_file ok", not err, text)
    err, text = client.tool("read_file", {"path": "hello.txt"})
    check("read_file renvoie le contenu", not err and "ligne 1" in text, text)

    print("\n-- read_file_lines --")
    err, text = client.tool("read_file_lines", {"path": "hello.txt", "startLine": 2, "maxLines": 1})
    check("read_file_lines (startLine=2)", not err and "ligne 2" in text and "ligne 1" not in text, text)

    print("\n-- create_directory / list_files --")
    err, text = client.tool("create_directory", {"path": "dossier"})
    check("create_directory ok", not err, text)
    err, text = client.tool("list_files", {"path": "."})
    check("list_files voit le dossier et le fichier", not err and "dossier" in text and "hello.txt" in text, text)

    print("\n-- get_file_info --")
    err, text = client.tool("get_file_info", {"path": "hello.txt"})
    check("get_file_info ok", not err and "hello.txt" in text, text)

    print("\n-- search_files --")
    err, text = client.tool("search_files", {"path": ".", "pattern": "ligne 2"})
    check("search_files trouve le texte", not err and "hello.txt" in text, text)

    print("\n-- move_file --")
    err, text = client.tool("move_file", {"oldPath": "hello.txt", "newPath": "rename.txt"})
    check("move_file ok", not err, text)
    err, text = client.tool("read_file", {"path": "rename.txt"})
    check("fichier renomme lisible", not err and "ligne 1" in text, text)

    print("\n-- securite : confinement a la racine --")
    for traversal in ("../escape.txt", "..\\..\\escape.txt", "dossier/../../escape.txt"):
        err, text = client.tool("read_file", {"path": traversal})
        check(f"travers refuse: {traversal}", err, text)

    print("\n-- securite : change_root --")
    err, text = client.tool("change_root", {"newRoot": str(Path.home()), "secret": "mauvais-secret"})
    check("change_root refuse avec mauvais secret", err, text)

    print("\n-- delete_file --")
    err, text = client.tool("delete_file", {"path": "rename.txt"})
    check("delete_file ok", not err, text)
    err, text = client.tool("read_file", {"path": "rename.txt"})
    check("fichier supprime illisible", err, text)


if __name__ == "__main__":
    main()
