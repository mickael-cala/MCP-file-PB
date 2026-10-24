# MCP-servers-PB — Serveurs MCP en PureBasic

Trois serveurs [MCP](https://modelcontextprotocol.io) (Model Context Protocol) écrits en **PureBasic**, 100 % natifs, qui exposent des outils à un client IA (Claude Desktop, Kimi Code, etc.) via **JSON-RPC 2.0 sur stdin/stdout** :

| Serveur | Source | Outil(s) | Description |
|---|---|---|---|
| **fileMCP** | `src/fileMCP.pb` | 10 outils | Gestion de fichiers confinée à une racine (`MCP_ROOT`) |
| **MCP-Fetch-PB** | `src/MCP-Fetch-PB.pb` | `fetch` | Récupération de pages web, conversion HTML → Markdown |
| **MCP-SequentialThinking-PB** | `src/MCP-SequentialThinking-PB.pb` | `sequential_thinking` | Raisonnement séquentiel structuré (étapes, révisions, branches) |

Caractéristiques communes :

- **Multi-plateforme** : Windows, Linux, macOS (sélection E/S stdio par directives `CompilerIf`).
- **Transport stdio** : chaque message JSON-RPC est émis sur une seule ligne, délimité par `\n`.
- **Zéro dépendance** : compilables avec PureBasic seul, aucune DLL/API externe.

## Outils MCP exposés

### fileMCP — gestion de fichiers

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

### MCP-Fetch-PB — récupération web

| Outil | Description | Paramètres |
|---|---|---|
| `fetch` | Récupère une URL et retourne son contenu en Markdown (ou HTML brut si `raw=true`) | `url`, `max_length` (défaut 5000), `start_index` (défaut 0), `raw` (défaut false) |

Les URLs non HTTP/HTTPS et les IPs littérales sont refusées (SSRF) ; un timeout plafonne la durée de chaque requête.

### MCP-SequentialThinking-PB — raisonnement séquentiel

| Outil | Description | Paramètres |
|---|---|---|
| `sequential_thinking` | Enregistre une étape de raisonnement et retourne l'état courant (numéro, total, historique, branches) | `thought`, `thoughtNumber`, `totalThoughts`, `nextThoughtNeeded`, `isRevision` (défaut false), `revisesThought` (défaut 0), `branchFromThought` (défaut 0), `branchId` |

⚠️ **Attention** : `write_file`, `delete_file`, `move_file` et `change_root` sont des opérations destructrices ou sensibles. Ne connectez ce serveur qu'à un répertoire dont la perte de contenu serait acceptable.

## Sécurité

| Variable d'environnement | Rôle | Serveur |
|---|---|---|
| `MCP_ROOT` | Répertoire racine autorisé pour toutes les opérations. Si absent, le répertoire courant du serveur est utilisé. | fileMCP |
| `MCP_ROOT_SECRET` | Mot de passe requis par l'outil `change_root` pour modifier la racine autorisée à chaud. | fileMCP |

Tous les chemins passés aux outils fileMCP sont normalisés et bloqués s'ils tentent de sortir de la racine autorisée. Voir [SECURITY.md](SECURITY.md).

## Compilation

Requiert [PureBasic](https://www.purebasic.com) et un format d'exécutable **Console**.

### Avec les scripts de build (recommandé)

```bash
build.bat      # Windows   -> genere build\fileMCP.exe, build\MCP-Fetch-PB.exe, build\MCP-SequentialThinking-PB.exe
./build.sh     # Linux/macOS -> memes noms sans extension
```

Les scripts compilent les 3 serveurs. Le compilateur est cherché dans la variable d'environnement `PBCOMPILER`, puis dans les chemins par défaut (`C:\Program Files\PureBasic\Compilers`, `C:\PureBasic\Compilers`), puis dans le `PATH`. Les exécutables sont générés dans `build/` (non versionné).

Pour nettoyer : `clean.bat` / `./clean.sh`.

### Via l'IDE PureBasic

Pour fileMCP, ouvrez le fichier projet de votre plateforme (`src/fileMCP_Windows.pbi`, `src/fileMCP_Linux.pbi`, `src/fileMCP_macOS.pbi`) et compilez (`F5`). Pour les deux autres serveurs, ouvrez directement le `.pb` dans l'IDE et compilez en format Console.

Les exécutables compilés ne sont pas versionnés : publiez-les via [GitHub Releases](https://docs.github.com/fr/repositories/releasing-projects-on-github) si besoin.

## Tests

Un harnais de tests fonctionnels (Python 3, sans dépendance) lance chaque serveur compilé et exerce ses outils, y compris les cas de sécurité (traversées de chemins, secret invalide, URLs invalides) :

```bash
python tests/test_mcp.py                          # les 3 serveurs
python tests/test_mcp.py fileMCP                  # un seul serveur
```

26 tests au total. Le binaire de chaque serveur est cherché dans `build/`, puis `src/` ; la variable `<NOM>_BIN` (ex. `FILEMCP_BIN`) force un chemin.

## Configuration d'un client MCP

Exemple générique (les trois serveurs) :

```json
{
  "mcpServers": {
    "file-pb": {
      "command": "/chemin/vers/build/fileMCP",
      "env": {
        "MCP_ROOT": "/chemin/vers/la/zone/autorisee",
        "MCP_ROOT_SECRET": "mot-de-passe-fort"
      }
    },
    "fetch-pb": {
      "command": "/chemin/vers/build/MCP-Fetch-PB"
    },
    "sequential-thinking-pb": {
      "command": "/chemin/vers/build/MCP-SequentialThinking-PB"
    }
  }
}
```

Sous Windows, les commandes pointent vers les `.exe` de `build\`, par ex. `C:\\chemin\\vers\\build\\fileMCP.exe`.

Chaque serveur démarre, attend les requêtes JSON-RPC sur stdin, et se termine proprement à l'EOF de stdin.

## Structure du dépôt

```
src/
├── fileMCP.pb                    # Serveur gestion de fichiers (multi-OS)
├── MCP-Fetch-PB.pb               # Serveur fetch web (HTML -> Markdown)
├── MCP-SequentialThinking-PB.pb  # Serveur raisonnement sequentiel
├── fileMCP_Windows.pbi           # Projet IDE PureBasic — Windows
├── fileMCP_Linux.pbi             # Projet IDE PureBasic — Linux
└── fileMCP_macOS.pbi             # Projet IDE PureBasic — macOS

build.bat / build.sh      # Compilation des 3 serveurs (sortie dans build/)
clean.bat / clean.sh      # Suppression des artefacts de compilation
tests/test_mcp.py         # Tests fonctionnels des 3 serveurs (JSON-RPC stdio)
```

## Documentation

- [CHANGELOG.md](CHANGELOG.md) — journal des versions
- [ROADMAP.md](ROADMAP.md) — feuille de route
- [ERRATA.md](ERRATA.md) — limitations et problèmes connus
- [CONTRIBUTING.md](CONTRIBUTING.md) — contribuer (conventions, tests)
- [SECURITY.md](SECURITY.md) — signalement de vulnérabilités, modèle de sécurité
- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) — code de conduite
- [AGENTS.md](AGENTS.md) — instructions pour les agents IA

## Licence

[MIT](LICENSE)
