# Feuille de route

## En cours de réflexion

- **Pagination** : `list_files` et `search_files` retournent tout en une seule
  réponse ; ajouter des paramètres `offset`/`limit` pour les gros répertoires.
- **Fichiers binaires** : lecture/écriture en base64 pour les fichiers non
  texte (aujourd'hui refusés).
- **Surchage JSON-RPC** : les réponses `tools/list` et les erreurs sont
  émises en une seule ligne ; documenter les limites de taille.

## Court terme

- Publier les exécutables Windows/Linux/macOS en [GitHub Releases](https://github.com/mickael-cala/MCP-file-PB/releases)
  et créer le tag `v1.0.0`.
- Étendre `tests/test_mcp.py` : concurrence, lignes très longues, encodages
  UTF-8 multioctets, EOF sans newline final.
- Journalisation optionnelle (stderr) pour le diagnostic.

## Moyen terme

- Outil `copy_file` et copie récursive de répertoire.
- Option `recursive` pour `delete_file` (aujourd'hui : dossier vide uniquement).
- Fichier de configuration (JSON) en alternative aux variables d'environnement.
- Notifications MCP `tools/list_changed` sur `change_root`.

## Non prévu

- Transport autre que stdio (SSE, HTTP) : le périmètre reste un serveur MCP
  local simple, sans dépendance.
