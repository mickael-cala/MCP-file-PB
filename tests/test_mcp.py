#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Tests fonctionnels des serveurs MCP (protocole JSON-RPC 2.0 sur stdio).

Serveurs testes :
    fileMCP                   gestion de fichiers (17 tests, racine temporaire)
    MCP-SequentialThinking-PB raisonnement sequentiel (local, sans reseau)
    MCP-Fetch-PB              recuperation web (catalogue + cas d'erreur hors
                              ligne ; le cas nominal necessite internet)

Chaque binaire est cherche dans l'ordre :
    1. variable d'environnement <NOM>_BIN (ex. FILEMCP_BIN)
    2. build/<nom>(.exe)
    3. src/<nom>(.exe)

Usage :
    python tests/test_mcp.py [nom-du-serveur ...]   # par defaut : tous
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


def find_binary(server):
    env_var = server.upper().replace("-", "_") + "_BIN"
    if os.environ.get(env_var):
        return Path(os.environ[env_var])
    exe = ".exe" if os.name == "nt" else ""
    base = Path(__file__).resolve().parent.parent
    for candidate in (f"build/{server}{exe}", f"src/{server}{exe}"):
        p = base / candidate
        if p.exists():
            return p
    return None


class McpClient:
    """Client JSON-RPC minimal : une ligne JSON par requete/reponse."""

    def __init__(self, binary, env_extra=None):
        env = os.environ.copy()
        if env_extra:
            env.update(env_extra)
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

    def tool_names(self):
        resp = self.call("tools/list")
        tools = (resp.get("result") or {}).get("tools") or []
        return [t.get("name") for t in tools]

    def close(self):
        if self.proc.stdin:
            self.proc.stdin.close()
        try:
            self.proc.wait(timeout=TIMEOUT)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()


# ---------------------------------------------------------------------------
# Suite fileMCP (gestion de fichiers)
# ---------------------------------------------------------------------------

def run_tests_filemcp():
    with tempfile.TemporaryDirectory(prefix="filemcp-test-") as tmp:
        root = Path(tmp)
        client = McpClient(find_binary("fileMCP"),
                           {"MCP_ROOT": str(root), "MCP_ROOT_SECRET": ROOT_SECRET})
        try:
            print("\n== fileMCP : tools/list ==")
            names = client.tool_names()
            expected = {
                "list_files", "read_file", "read_file_lines", "write_file",
                "create_directory", "delete_file", "move_file", "get_file_info",
                "search_files", "change_root",
            }
            check("tools/list retourne 10 outils", len(names) == 10, f"obtenu: {names}")
            check("catalogue conforme", set(names) == expected, f"diff: {set(names) ^ expected}")

            print("\n== fileMCP : write_file / read_file ==")
            err, text = client.tool("write_file", {"path": "hello.txt", "content": "ligne 1\nligne 2\n"})
            check("write_file ok", not err, text)
            err, text = client.tool("read_file", {"path": "hello.txt"})
            check("read_file renvoie le contenu", not err and "ligne 1" in text, text)

            print("\n== fileMCP : read_file_lines ==")
            err, text = client.tool("read_file_lines", {"path": "hello.txt", "startLine": 2, "maxLines": 1})
            check("read_file_lines (startLine=2)", not err and "ligne 2" in text and "ligne 1" not in text, text)

            print("\n== fileMCP : create_directory / list_files ==")
            err, text = client.tool("create_directory", {"path": "dossier"})
            check("create_directory ok", not err, text)
            err, text = client.tool("list_files", {"path": "."})
            check("list_files voit le dossier et le fichier", not err and "dossier" in text and "hello.txt" in text, text)

            print("\n== fileMCP : get_file_info ==")
            err, text = client.tool("get_file_info", {"path": "hello.txt"})
            check("get_file_info ok", not err and "hello.txt" in text, text)

            print("\n== fileMCP : search_files ==")
            err, text = client.tool("search_files", {"path": ".", "pattern": "ligne 2"})
            check("search_files trouve le texte", not err and "hello.txt" in text, text)

            print("\n== fileMCP : move_file ==")
            err, text = client.tool("move_file", {"oldPath": "hello.txt", "newPath": "rename.txt"})
            check("move_file ok", not err, text)
            err, text = client.tool("read_file", {"path": "rename.txt"})
            check("fichier renomme lisible", not err and "ligne 1" in text, text)

            print("\n== fileMCP : securite - confinement a la racine ==")
            for traversal in ("../escape.txt", "..\\..\\escape.txt", "dossier/../../escape.txt"):
                err, text = client.tool("read_file", {"path": traversal})
                check(f"travers refuse: {traversal}", err, text)

            print("\n== fileMCP : securite - change_root ==")
            err, text = client.tool("change_root", {"newRoot": str(Path.home()), "secret": "mauvais-secret"})
            check("change_root refuse avec mauvais secret", err, text)

            print("\n== fileMCP : delete_file ==")
            err, text = client.tool("delete_file", {"path": "rename.txt"})
            check("delete_file ok", not err, text)
            err, text = client.tool("read_file", {"path": "rename.txt"})
            check("fichier supprime illisible", err, text)
        finally:
            client.close()


# ---------------------------------------------------------------------------
# Suite MCP-SequentialThinking-PB
# ---------------------------------------------------------------------------

def run_tests_sequential():
    client = McpClient(find_binary("MCP-SequentialThinking-PB"))
    try:
        print("\n== SequentialThinking : tools/list ==")
        names = client.tool_names()
        check("catalogue = [sequential_thinking]", names == ["sequential_thinking"], f"obtenu: {names}")

        print("\n== SequentialThinking : sequential_thinking ==")
        err, text = client.tool("sequential_thinking", {
            "thought": "Etape 1 : analyser le probleme.",
            "thoughtNumber": 1, "totalThoughts": 3, "nextThoughtNeeded": True,
        })
        check("etape 1 acceptee", not err, text)
        check("etat retourne (etape/total)", "1" in text and "3" in text, text)

        err, text = client.tool("sequential_thinking", {
            "thought": "Etape 2 : proposer une solution.",
            "thoughtNumber": 2, "totalThoughts": 3, "nextThoughtNeeded": True,
        })
        check("etape 2 acceptee", not err, text)

        err, text = client.tool("sequential_thinking", {
            "thought": "Revision de l'etape 1.",
            "thoughtNumber": 3, "totalThoughts": 3, "nextThoughtNeeded": False,
            "isRevision": True, "revisesThought": 1,
        })
        check("revision acceptee", not err, text)
        check("historique mis a jour (3 etapes)", '"thoughtHistoryLength":3' in text, text)
    finally:
        client.close()


# ---------------------------------------------------------------------------
# Suite MCP-Fetch-PB
# ---------------------------------------------------------------------------

def run_tests_fetch():
    client = McpClient(find_binary("MCP-Fetch-PB"))
    try:
        print("\n== Fetch : tools/list ==")
        names = client.tool_names()
        check("catalogue = [fetch]", names == ["fetch"], f"obtenu: {names}")

        print("\n== Fetch : cas d'erreur hors ligne ==")
        err, text = client.tool("fetch", {"url": "http://127.0.0.1:9/"})
        check("connexion refusee signalee en erreur", err, text[:120])

        err, text = client.tool("fetch", {"url": "not-a-url"})
        check("URL invalide signalee en erreur", err, text[:120])
    finally:
        client.close()


SUITES = {
    "fileMCP": run_tests_filemcp,
    "MCP-SequentialThinking-PB": run_tests_sequential,
    "MCP-Fetch-PB": run_tests_fetch,
}


def main():
    requested = sys.argv[1:] or list(SUITES)
    missing = [s for s in requested if s not in SUITES]
    if missing:
        print(f"Suites inconnues : {missing}. Disponibles : {list(SUITES)}")
        sys.exit(2)

    skipped = []
    for server in requested:
        binary = find_binary(server)
        if binary is None:
            skipped.append(server)
            print(f"[SKIP] {server} : binaire introuvable "
                  f"(compilez avec build.bat / build.sh ou definissez "
                  f"{server.upper().replace('-', '_')}_BIN)")
            continue
        print(f"\nBinaire teste : {binary}")
        SUITES[server]()

    print(f"\n{passed} reussis, {failed} echoues, {len(skipped)} ignores")
    sys.exit(0 if failed == 0 and not skipped else 1)


if __name__ == "__main__":
    main()
