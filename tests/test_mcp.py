#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Tests fonctionnels des serveurs MCP, via le harnais tests/mcp_client.py.

Serveurs testes :
    fileMCP                   gestion de fichiers (racine temporaire)
    MCP-SequentialThinking-PB raisonnement sequentiel (local, sans reseau)
    MCP-Fetch-PB              recuperation web (catalogue + cas d'erreur hors
                              ligne ; le cas nominal necessite internet)

Chaque binaire est cherche dans l'ordre :
    1. variable d'environnement <NOM>_BIN (ex. FILEMCP_BIN)
    2. build/<nom>(.exe)
    3. src/<nom>(.exe)

Usage :
    python tests/test_mcp.py [nom-du-serveur ...]   # par defaut : les 3
"""

import os
import sys
import tempfile
from pathlib import Path

from mcp_client import MCPTestClient

ROOT_SECRET = "test-secret-123"

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


# ---------------------------------------------------------------------------
# Suite fileMCP (gestion de fichiers)
# ---------------------------------------------------------------------------

def run_tests_filemcp():
    with tempfile.TemporaryDirectory(prefix="filemcp-test-") as tmp:
        env = {"MCP_ROOT": tmp, "MCP_ROOT_SECRET": ROOT_SECRET}
        with MCPTestClient(find_binary("fileMCP"), env=env) as client:
            run_checks_filemcp(client, Path(tmp))


def run_checks_filemcp(client, root):
    print("\n== fileMCP : tools/list ==")
    names = client.list_tools()
    expected = {
        "list_files", "read_file", "read_file_lines", "write_file",
        "create_directory", "delete_file", "move_file", "get_file_info",
        "search_files", "change_root",
    }
    check("tools/list retourne 10 outils", len(names) == 10, f"obtenu: {names}")
    check("catalogue conforme", set(names) == expected, f"diff: {set(names) ^ expected}")

    print("\n== fileMCP : write_file / read_file ==")
    err, text = client.tool_text("write_file", {"path": "hello.txt", "content": "ligne 1\nligne 2\n"})
    check("write_file ok", not err, text)
    err, text = client.tool_text("read_file", {"path": "hello.txt"})
    check("read_file renvoie le contenu", not err and "ligne 1" in text, text)

    print("\n== fileMCP : read_file_lines ==")
    err, text = client.tool_text("read_file_lines", {"path": "hello.txt", "startLine": 2, "maxLines": 1})
    check("read_file_lines (startLine=2)", not err and "ligne 2" in text and "ligne 1" not in text, text)

    print("\n== fileMCP : create_directory / list_files ==")
    err, text = client.tool_text("create_directory", {"path": "dossier"})
    check("create_directory ok", not err, text)
    err, text = client.tool_text("list_files", {"path": "."})
    check("list_files voit le dossier et le fichier", not err and "dossier" in text and "hello.txt" in text, text)

    print("\n== fileMCP : get_file_info ==")
    err, text = client.tool_text("get_file_info", {"path": "hello.txt"})
    check("get_file_info ok", not err and "hello.txt" in text, text)

    print("\n== fileMCP : search_files ==")
    err, text = client.tool_text("search_files", {"path": ".", "pattern": "ligne 2"})
    check("search_files trouve le texte", not err and "hello.txt" in text, text)

    print("\n== fileMCP : move_file ==")
    err, text = client.tool_text("move_file", {"oldPath": "hello.txt", "newPath": "rename.txt"})
    check("move_file ok", not err, text)
    err, text = client.tool_text("read_file", {"path": "rename.txt"})
    check("fichier renomme lisible", not err and "ligne 1" in text, text)

    print("\n== fileMCP : securite - confinement a la racine ==")
    for traversal in ("../escape.txt", "..\\..\\escape.txt", "dossier/../../escape.txt"):
        err, text = client.tool_text("read_file", {"path": traversal})
        check(f"travers refuse: {traversal}", err, text)

    print("\n== fileMCP : securite - change_root ==")
    err, text = client.tool_text("change_root", {"newRoot": str(Path.home()), "secret": "mauvais-secret"})
    check("change_root refuse avec mauvais secret", err, text)

    print("\n== fileMCP : delete_file ==")
    err, text = client.tool_text("delete_file", {"path": "rename.txt"})
    check("delete_file ok", not err, text)
    err, text = client.tool_text("read_file", {"path": "rename.txt"})
    check("fichier supprime illisible", err, text)


# ---------------------------------------------------------------------------
# Suite MCP-SequentialThinking-PB
# ---------------------------------------------------------------------------

def run_tests_sequential():
    with MCPTestClient(find_binary("MCP-SequentialThinking-PB")) as client:
        print("\n== SequentialThinking : tools/list ==")
        names = client.list_tools()
        check("catalogue = [sequential_thinking]", names == ["sequential_thinking"], f"obtenu: {names}")

        print("\n== SequentialThinking : sequential_thinking ==")
        err, text = client.tool_text("sequential_thinking", {
            "thought": "Etape 1 : analyser le probleme.",
            "thoughtNumber": 1, "totalThoughts": 3, "nextThoughtNeeded": True,
        })
        check("etape 1 acceptee", not err, text)
        check("etat retourne (etape/total)", "1" in text and "3" in text, text)

        err, text = client.tool_text("sequential_thinking", {
            "thought": "Etape 2 : proposer une solution.",
            "thoughtNumber": 2, "totalThoughts": 3, "nextThoughtNeeded": True,
        })
        check("etape 2 acceptee", not err, text)

        err, text = client.tool_text("sequential_thinking", {
            "thought": "Revision de l'etape 1.",
            "thoughtNumber": 3, "totalThoughts": 3, "nextThoughtNeeded": False,
            "isRevision": True, "revisesThought": 1,
        })
        check("revision acceptee", not err, text)
        check("historique mis a jour (3 etapes)", '"thoughtHistoryLength":3' in text, text)


# ---------------------------------------------------------------------------
# Suite MCP-Fetch-PB
# ---------------------------------------------------------------------------

def run_tests_fetch():
    with MCPTestClient(find_binary("MCP-Fetch-PB")) as client:
        print("\n== Fetch : tools/list ==")
        names = client.list_tools()
        check("catalogue = [fetch]", names == ["fetch"], f"obtenu: {names}")

        print("\n== Fetch : cas d'erreur hors ligne ==")
        err, text = client.tool_text("fetch", {"url": "http://127.0.0.1:9/"})
        check("connexion refusee signalee en erreur", err, text[:120])

        err, text = client.tool_text("fetch", {"url": "not-a-url"})
        check("URL invalide signalee en erreur", err, text[:120])


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
