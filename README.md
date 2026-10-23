# MCP-file-PB — Serveur MCP de gestion de fichiers en PureBasic

Serveur [MCP](https://modelcontextprotocol.io) (Model Context Protocol) écrit en **PureBasic**, 100 % natif (aucune DLL/API externe), qui expose des outils de gestion de fichiers à un client IA (Claude Desktop, Kimi Code, etc.) via **JSON-RPC 2.0 sur stdin/stdout**.

- **Multi-plateforme** : Windows, Linux, macOS (un seul code source, sélection E/S stdio par directives `CompilerIf`).
- **Transport stdio** : chaque message JSON-RPC est émis sur une seule ligne, délimité par `\n`.
- **Sécurité par confinement** : toutes les opérations sont limitées à une racine autorisée (`MCP_ROOT`), avec normalisation des chemins (protection contre les traversées `..`).

## Outils MCP exposés

| Outil | Description | Paramètres |
|---|---|---|
| `list_files` | Lister le contenu d'un répertoire (confiné à la racine autorisée) | `path` |
| `read_file` | Lire un fichier texte (tronqué au-delà de 20 000 octets) | `path` |
| `read_file_lines` | Lire une plage de lignes (fichier limité à 5 Mo) | `path`, `startLine` (défaut 1), `maxLines` (défaut 50) |
| `write_file` | Écrire/créer un fichier texte | `path`, `content` |
| `create_directory` | Créer un répertoire | `path` |
| `delete_file` | Supprimer un fichier ou dossier vide ⚠️ | `path` |
| `move_file` | Déplacer ou renommer un fichier ⚠️ | `oldPath`, `newPath` |
| `get_file_info` | Infos détaillées fichier/dossier | `path` |
| `search_files` | Rechercher du texte (récursif) | `path`, `pattern` |
| `change_root` | Changer la zone autorisée ⚠️ | `newRoot`, `secret` |

⚠️ **Attention** : `write_file`, `delete_file`, `move_file` et `change_root` sont des opérations destructrices ou sensibles. Ne connectez ce serveur qu'à un répertoire dont la perte de contenu serait acceptable.

## Sécurité

| Variable d'environnement | Rôle |
|---|---|
| `MCP_ROOT` | Répertoire racine autorisé pour toutes les opérations. Si absent, le répertoire courant du serveur est utilisé. |
| `MCP_ROOT_SECRET` | Mot de passe requis par l'outil `change_root` pour modifier la racine autorisée à chaud. |

Tous les chemins passés aux outils sont normalisés et bloqués s'ils tentent de sortir de la racine autorisée.

## Compilation

Requiert [PureBasic](https://www.purebasic.com) et un format d'exécutable **Console**.

### Avec les scripts de build (recommandé)

```bash
build.bat      # Windows  -> genere build\fileMCP.exe
./build.sh     # Linux/macOS -> genere build/fileMCP
```

Les scripts cherchent le compilateur dans la variable d'environnement `PBCOMPILER`, puis dans le chemin par défaut (`C:\PureBasic\Compilers` sous Windows), puis dans le `PATH`. L'exécutable est généré dans `build/` (non versionné).

Pour nettoyer : `clean.bat` / `./clean.sh`.

### Via l'IDE PureBasic

1. Dans l'IDE PureBasic, ouvrez le fichier projet de votre plateforme :
   - Windows : `src/fileMCP_Windows.pbi`
   - Linux : `src/fileMCP_Linux.pbi`
   - macOS : `src/fileMCP_macOS.pbi`
2. Compilez (`F5`). Le fichier projet configure déjà le format Console et le nom de l'exécutable.

Les exécutables compilés ne sont pas versionnés : publiez-les via [GitHub Releases](https://docs.github.com/fr/repositories/releasing-projects-on-github) si besoin.

## Tests

Un harnais de tests fonctionnels (Python 3, sans dépendance) lance le serveur compilé avec une racine temporaire et exerce les 10 outils MCP, y compris les cas de sécurité (refus des traversées de chemins, `change_root` avec mauvais secret) :

```bash
python tests/test_mcp.py
```

Le binaire testé est cherché dans `build/`, puis `src/` (variable `FILEMCP_BIN` pour forcer un chemin).

## Configuration d'un client MCP

Exemple générique :

```json
{
  "mcpServers": {
    "file-pb": {
      "command": "/chemin/vers/fileMCP",
      "env": {
        "MCP_ROOT": "/chemin/vers/la/zone/autorisee",
        "MCP_ROOT_SECRET": "mot-de-passe-fort"
      }
    }
  }
}
```

Sous Windows, remplacez `command` par le chemin vers l'`.exe` compilé, par ex. `C:\\PureBasic\\filemcpserver.exe`.

Le serveur démarre, attend les requêtes JSON-RPC sur stdin, et se termine proprement à l'EOF de stdin.

## Structure du dépôt

```
src/
├── fileMCP.pb            # Code source unique (multi-OS)
├── fileMCP_Windows.pbi   # Projet IDE PureBasic — Windows
├── fileMCP_Linux.pbi     # Projet IDE PureBasic — Linux
└── fileMCP_macOS.pbi     # Projet IDE PureBasic — macOS

build.bat / build.sh      # Compilation (sortie dans build/, non versionne)
clean.bat / clean.sh      # Suppression des artefacts de compilation
tests/test_mcp.py         # Tests fonctionnels (JSON-RPC sur stdio)
```

## Licence

[MIT](LICENSE)
