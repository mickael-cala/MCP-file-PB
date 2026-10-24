#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Client MCP de test (harnais externe) - Phase 0 du plan.

Lance un serveur MCP en sous-processus, dialogue en JSON-RPC 2.0 sur
stdio (une ligne JSON par message) et valide la conformite des reponses.

Usage :
    from mcp_client import MCPTestClient

    client = MCPTestClient("build/fileMCP.exe", env={"MCP_ROOT": "/tmp/x"})
    result = client.call_tool("list_files", {"path": "."})
    assert not result["isError"]
    client.close()
"""

import json
import os
import subprocess
import time


class MCPError(Exception):
    """Erreur de conformite du protocole MCP cote serveur."""


class MCPTestClient:
    """Client JSON-RPC 2.0 minimal pour tester un serveur MCP stdio."""

    def __init__(self, executable, env=None, timeout=10, auto_initialize=True):
        self.timeout = timeout
        full_env = os.environ.copy()
        if env:
            full_env.update(env)
        self.proc = subprocess.Popen(
            [str(executable)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=full_env,
            text=True,
            encoding="utf-8",
        )
        self.next_id = 0
        if auto_initialize:
            resp = self.request("initialize", {})
            self._validate_initialize(resp)

    # ------------------------------------------------------------------
    # Protocole de base
    # ------------------------------------------------------------------
    def request(self, method, params=None):
        """Envoie une requete et retourne la reponse validee."""
        self.next_id += 1
        req = {"jsonrpc": "2.0", "id": self.next_id, "method": method}
        if params is not None:
            req["params"] = params
        self._send(req)
        resp = self._recv()
        self._validate_response(resp, self.next_id)
        return resp

    def call_tool(self, name, arguments=None):
        """
        Appelle tools/call et retourne l'objet result complet :
            {"content": [{"type": "text", "text": "..."}], "isError": bool}
        """
        resp = self.request(
            "tools/call",
            {"name": name, "arguments": arguments or {}},
        )
        result = resp.get("result") or {}
        if "content" not in result or "isError" not in result:
            raise MCPError(f"resultat tools/call incomplet : {result!r}")
        return result

    def tool_text(self, name, arguments=None):
        """Appelle un outil et retourne (isError, texte_du_premier_contenu)."""
        result = self.call_tool(name, arguments)
        content = result.get("content") or []
        text = content[0].get("text", "") if content else ""
        return bool(result.get("isError")), text

    def list_tools(self):
        """Retourne la liste des noms d'outils du catalogue."""
        resp = self.request("tools/list")
        tools = (resp.get("result") or {}).get("tools") or []
        return [t.get("name") for t in tools]

    def notify_initialized(self):
        """Envoie la notification notifications/initialized (sans reponse)."""
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    # ------------------------------------------------------------------
    # Envoi / reception bas niveau
    # ------------------------------------------------------------------
    def _send(self, obj):
        try:
            self.proc.stdin.write(json.dumps(obj) + "\n")
            self.proc.stdin.flush()
        except (BrokenPipeError, ValueError) as exc:
            raise MCPError(f"impossible d'ecrire sur stdin du serveur : {exc}")

    def _recv(self):
        deadline = time.time() + self.timeout
        while time.time() < deadline:
            line = self.proc.stdout.readline()
            if not line:
                stderr = self._read_stderr()
                raise MCPError(
                    f"stdout ferme sans reponse (stderr: {stderr[:300]})"
                )
            line = line.strip()
            if not line:
                continue
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                # Le serveur a emis une ligne non JSON : protocole viole
                raise MCPError(f"ligne non JSON recue : {line[:200]!r}")
        raise MCPError(f"timeout apres {self.timeout}s en attente de reponse")

    def _read_stderr(self):
        try:
            return self.proc.stderr.read() or ""
        except Exception:
            return ""

    # ------------------------------------------------------------------
    # Validations de conformite JSON-RPC 2.0
    # ------------------------------------------------------------------
    def _validate_response(self, resp, expected_id):
        if not isinstance(resp, dict):
            raise MCPError(f"reponse non objet : {resp!r}")
        if resp.get("jsonrpc") != "2.0":
            raise MCPError(f"champ jsonrpc invalide : {resp!r}")
        if resp.get("id") != expected_id:
            raise MCPError(
                f"id incoherent (attendu {expected_id}, recu {resp.get('id')})"
            )
        if ("result" in resp) == ("error" in resp):
            raise MCPError(
                f"reponse doit contenir exactement un de result/error : {resp!r}"
            )

    def _validate_initialize(self, resp):
        result = resp.get("result") or {}
        if "protocolVersion" not in result:
            raise MCPError(f"initialize sans protocolVersion : {result!r}")
        if "serverInfo" not in result:
            raise MCPError(f"initialize sans serverInfo : {result!r}")

    # ------------------------------------------------------------------
    # Cycle de vie
    # ------------------------------------------------------------------
    def close(self):
        """Ferme stdin (EOF -> arret propre du serveur) et attend la fin."""
        if self.proc.stdin:
            try:
                self.proc.stdin.close()
            except (BrokenPipeError, ValueError):
                pass
        try:
            self.proc.wait(timeout=self.timeout)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False
