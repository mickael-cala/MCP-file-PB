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
import re
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


# ---------------------------------------------------------------------------
# Suite memoryMCP (graphe d'entites SQLite)
# ---------------------------------------------------------------------------

def run_tests_memory():
    with tempfile.TemporaryDirectory(prefix="memorymcp-test-") as tmp:
        env = {"MCP_MEMORY_DB": str(Path(tmp) / "memory.db")}
        with MCPTestClient(find_binary("memoryMCP"), env=env) as client:
            run_checks_memory(client)


def run_checks_memory(client):
    print("\n== Memory : tools/list ==")
    names = client.list_tools()
    expected = {
        "create_entities", "create_relations", "add_observations",
        "delete_entities", "delete_observations", "delete_relations",
        "read_graph", "search_nodes", "open_nodes",
    }
    check("tools/list retourne 9 outils", len(names) == 9, f"obtenu: {names}")
    check("catalogue conforme", set(names) == expected, f"diff: {set(names) ^ expected}")

    print("\n== Memory : cycle complet create -> search -> add -> delete ==")
    err, text = client.tool_text("create_entities", {"entities": [
        {"name": "Alice", "entityType": "person", "observations": ["aime le cafe"]},
        {"name": "Bob", "entityType": "person", "observations": []},
    ]})
    check("create_entities ok", not err, text)

    err, text = client.tool_text("create_relations", {"relations": [
        {"from": "Alice", "to": "Bob", "relationType": "connait"},
    ]})
    check("create_relations ok", not err, text)

    err, text = client.tool_text("search_nodes", {"query": "cafe"})
    check("search_nodes trouve par observation", not err and "Alice" in text, text[:120])

    err, text = client.tool_text("search_nodes", {"query": "bob"})
    check("search_nodes insensible a la casse", not err and "Bob" in text, text[:120])

    err, text = client.tool_text("add_observations", {"observations": [
        {"entityName": "Alice", "contents": ["deuxieme observation"]},
    ]})
    check("add_observations ok", not err, text)

    err, text = client.tool_text("open_nodes", {"names": ["Alice", "Bob"]})
    check("open_nodes retourne les 2 entites", not err and "Alice" in text and "Bob" in text, text[:120])
    check("observation ajoutee visible", "deuxieme observation" in text)

    err, text = client.tool_text("read_graph", {})
    check("read_graph contient la relation", not err and "connait" in text, text[:120])

    print("\n== Memory : securite et erreurs ==")
    err, text = client.tool_text("create_entities", {"entities": [
        {"name": "Robert'); DROP TABLE entities;--", "entityType": "person"},
    ]})
    check("injection SQL echappee", not err, text[:120])
    err, text = client.tool_text("read_graph", {})
    check("table intacte apres injection", not err, text[:120])

    err, text = client.tool_text("create_relations", {"relations": [
        {"from": "Inconnu", "to": "Bob", "relationType": "x"},
    ]})
    check("relation sur entite inconnue refusee", err, text[:120])

    err, text = client.tool_text("add_observations", {"observations": [
        {"entityName": "Fantome", "contents": ["x"]},
    ]})
    check("observation sur entite inconnue refusee", err, text[:120])

    print("\n== Memory : suppressions ==")
    err, text = client.tool_text("delete_observations", {"observations": [
        {"entityName": "Alice", "contents": ["aime le cafe"]},
    ]})
    check("delete_observations ok", not err, text)
    err, text = client.tool_text("delete_relations", {"relations": [
        {"from": "Alice", "to": "Bob", "relationType": "connait"},
    ]})
    check("delete_relations ok", not err, text)
    err, text = client.tool_text("delete_entities", {"entityNames": ["Alice"]})
    check("delete_entities ok", not err, text)
    err, text = client.tool_text("open_nodes", {"names": ["Alice"]})
    compact = re.sub(r"\s+", "", text)
    check("Alice supprimee (cascade)", not err and '"entities":[]' in compact, text[:120])


# ---------------------------------------------------------------------------
# Suite dbMCP (exploration SQL, SQLite + PostgreSQL optionnel)
# ---------------------------------------------------------------------------

def run_tests_database():
    with tempfile.TemporaryDirectory(prefix="dbmcp-test-") as tmp:
        env = {"MCP_DB_PATH": str(Path(tmp) / "test.db")}
        with MCPTestClient(find_binary("dbMCP"), env=env) as client:
            run_checks_database(client)
        run_checks_database_postgres(env)


def run_checks_database_postgres(base_env):
    """T2.9-T2.12 : executes uniquement si un DSN PostgreSQL de test est fourni."""
    print("\n== Database : PostgreSQL (T2.9-T2.12) ==")
    dsn = os.environ.get("MCP_DB_POSTGRES_TEST_DSN")
    if not dsn:
        print("  [SKIP] definir MCP_DB_POSTGRES_TEST_DSN pour executer les tests PostgreSQL")
        return
    env = dict(base_env)
    env["MCP_DB_POSTGRES_DSN"] = dsn
    with MCPTestClient(find_binary("dbMCP"), env=env) as client:
        err, text = client.tool_text("db_list_schemas", {"engine": "postgres"})
        check("T2.9 list_schemas retourne public", not err and "public" in text, text[:120])
        err, text = client.tool_text("db_list_tables", {"engine": "postgres"})
        check("T2.9b list_tables postgres ok", not err, text[:120])
        err, text = client.tool_text("db_execute_query", {
            "engine": "postgres",
            "query": "SELECT table_name FROM information_schema.tables WHERE table_schema='public' LIMIT 1",
        })
        check("T2.12 requete information_schema ok", not err, text[:120])
    # Connexion invalide : le serveur doit demarrer quand meme et rejeter proprement
    bad_env = dict(base_env)
    bad_env["MCP_DB_POSTGRES_DSN"] = "host=127.0.0.1 port=9 dbname=rien connect_timeout=2"
    with MCPTestClient(find_binary("dbMCP"), env=bad_env) as client:
        err, text = client.tool_text("db_list_schemas", {"engine": "postgres"})
        check("T2.11 connexion postgres invalide -> erreur claire, serveur vivant", err, text[:120])


def run_checks_database(client):
    print("\n== Database : tools/list ==")
    names = client.list_tools()
    expected = {
        "db_list_schemas", "db_list_tables", "db_describe_table",
        "db_execute_query", "db_explain",
    }
    check("tools/list retourne 5 outils", len(names) == 5, f"obtenu: {names}")
    check("catalogue conforme", set(names) == expected, f"diff: {set(names) ^ expected}")

    print("\n== Database : lecture seule (defaut) ==")
    err, text = client.tool_text("db_execute_query", {"query": "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)"})
    check("CREATE refuse sans MCP_DB_ALLOW_WRITE", err, text[:100])
    err, text = client.tool_text("db_execute_query", {"query": "INSERT INTO users (name) VALUES ('x')"})
    check("INSERT refuse", err, text[:100])
    err, text = client.tool_text("db_execute_query", {"query": "DROP TABLE users"})
    check("DROP refuse", err, text[:100])
    err, text = client.tool_text("db_execute_query", {"query": "WITH x AS (SELECT 1) DELETE FROM t"})
    check("CTE avec DELETE refuse", err, text[:100])

    print("\n== Database : requetes en lecture ==")
    err, text = client.tool_text("db_execute_query", {"query": "SELECT 1 AS un, 'x' AS t, 2.5 AS f, NULL AS vide"})
    check("SELECT expression ok", not err, text[:120])
    check("NULL preserve en JSON", ",null]" in text.replace(" ", ""), text[:120])
    err, text = client.tool_text("db_execute_query", {"query": "SELECT * FROM table_inexistante"})
    check("requete invalide -> erreur claire", err, text[:120])

    print("\n== Database : schemas / engine ==")
    err, text = client.tool_text("db_list_schemas", {})
    check("sqlite -> [main]", not err and "main" in text, text[:120])
    err, text = client.tool_text("db_list_tables", {"engine": "moteur_fou"})
    check("engine invalide -> erreur", err, text[:120])
    err, text = client.tool_text("db_list_tables", {"engine": "postgres"})
    check("postgres non configure -> erreur", err, text[:120])


SUITES = {
    "fileMCP": run_tests_filemcp,
    "MCP-SequentialThinking-PB": run_tests_sequential,
    "MCP-Fetch-PB": run_tests_fetch,
    "memoryMCP": run_tests_memory,
    "dbMCP": run_tests_database,
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
