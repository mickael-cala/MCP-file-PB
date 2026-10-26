# Sécurité

## Signaler une vulnérabilité

**Ne publiez pas de vulnérabilité dans les issues publiques.**

Ouvrez plutôt un avis de sécurité privé via
[GitHub Security Advisories](https://github.com/mickael-cala/MCPserver-StdioSuite/security/advisories/new)
(contact : `mickael-cala`). Vous recevrez une réponse sous quelques jours ;
une correction sera publiée avant toute divulgation publique.

## Modèle de sécurité

Le dépôt contient 8 serveurs MCP, chacun avec ses garde-fous :

| Serveur | Surface | Protections |
|---|---|---|
| `fileMCP` | Système de fichiers | Confinement à `MCP_ROOT`, normalisation des chemins (traversées `..` refusées), suppression récursive uniquement sur `recursive=true`, binaires refusés en lecture, `change_root` protégé par `MCP_ROOT_SECRET` |
| `memoryMCP` | Base SQLite | Échappement SQL (apostrophes doublées), FK en cascade, base locale (`MCP_MEMORY_DB`) |
| `dbMCP` | Bases SQL | **Lecture seule par défaut** (`IsReadOnlyQuery`), écritures uniquement avec `MCP_DB_ALLOW_WRITE=1`, refus journalisés |
| `context7MCP` | API web | HTTP/HTTPS uniquement, clé API jamais loggée (WinHTTP/curl) |
| `gitMCP` | Sous-processus git | `GitSafeParam` rejette les métacaractères shell sur tous les paramètres, aucune commande exécutée sans validation |
| `githubMCP` | API GitHub | Écritures exigeant `confirm=true`, token jamais renvoyé ni loggé, pagination bornée, validation des segments d'URL (WinHTTP/curl) |
| `MCP-Fetch-PB` | API web | HTTP/HTTPS uniquement, hôte résolu et **toutes** ses adresses validées (refus privé/loopback/link-local/CGNAT/multicast/ULA/IPv4-mappée, fail-closed), redirections non suivies automatiquement (3 sauts maximum, chaque cible revalidée) |
| `MCP-SequentialThinking-PB` | État local | Aucune I/O externe |

### Validation réseau (anti-SSRF)

`MCP-Fetch-PB` ne juge jamais un hôte sur sa chaîne : il le résout via
`getaddrinfo` et refuse la requête si **une seule** adresse retournée est non
globale. Une résolution impossible est un refus. Les redirections sont
désactivées au niveau du client HTTP (WinHTTP `DISABLE_REDIRECTS`, curl sans
`-L`) puis suivies manuellement : 3 sauts maximum, chaque cible repassant par
la même validation avant toute connexion.

## Secrets et variables d'environnement

| Variable | Sensibilité | Recommandation |
|---|---|---|
| `MCP_ROOT_SECRET` | Mot de passe | Valeur forte, non réutilisée |
| `MCP_GITHUB_TOKEN` | Token PAT | Scope minimal (lecture seule si possible), rotation régulière |
| `MCP_CONTEXT7_API_KEY` | Clé API | Prefixe `ctx7sk`, rotation si fuite |
| `MCP_DB_POSTGRES_DSN` | Peut contenir un mot de passe | Préférer un utilisateur dédié en lecture seule |

Règles générales :

- Les serveurs ne renvoient **jamais** un secret dans une réponse MCP ; les
  logs vont sur **stderr** (jamais stdout, qui porte le protocole).
- Ne lancez les serveurs qu'en local : le transport est stdio, sans
  authentification client. La sécurité repose sur le processus, son
  environnement et les droits de l'utilisateur.
- Ne connectez `fileMCP` qu'à un répertoire dont la perte de contenu serait
  acceptable (outils destructeurs : `write_file`, `delete_file`, `move_file`,
  `change_root`).
- `dbMCP` en écriture (`MCP_DB_ALLOW_WRITE=1`) doit pointer une base de test
  ou un utilisateur SQL aux droits limités.

## Sécurité du code

Voir [CONTRIBUTING.md](CONTRIBUTING.md). Les cas de sécurité sont couverts par
les tests : traversées de chemins (fileMCP), injection SQL (memory/db),
injection shell (git), garde `confirm` et gestion d'erreurs (github),
anti-SSRF (fetch), refus d'écriture SQL (db).
