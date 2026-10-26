# Feuille de route

Les 8 serveurs MCP (phases 0 à 7, voir [PLAN.md](PLAN.md)) sont livrés, la
**v1.0.0** est publiée et le durcissement sécurité/conformité (Phase 7 :
anti-SSRF par résolution DNS, redirections bornées, `isError` explicite,
conformité JSON-RPC) est appliqué. Cette feuille de route couvre la suite.

## Court terme

- **Valider macOS** (le code et `build.sh` sont prêts ; prérequis : `curl`),
  puis publier les binaires **Linux** et **macOS** dans une release `v1.0.1`
  avec `SHA256SUMS`.
- Ajouter une **CI GitHub Actions** (matrice Windows/Linux) si un runner avec
  PureBasic sous licence devient disponible.

## Moyen terme

- **Fetch/SequentialThinking** : extraction HTML→Markdown plus riche (tableaux,
  code), persistance optionnelle de l'historique de raisonnement.
- **FileMCP** : `copy_file`, pagination de `list_files`/`search_files`,
  lecture binaire base64 (la suppression récursive est livrée : `recursive=true`).
- **Memory** : recherche plein texte (FTS5), export/import JSON du graphe.
- **Database** : PostgreSQL avec binding de paramètres, `db_explain` formaté.
- **Git** : `git_log` avec plage de dates, `git_diff --stat`, `--no-color`.
- **GitHub** : commentaires d'issues, review de PR, pagination automatique.
- **Context7** : cache local des réponses par bibliothèque.
- Fichier de configuration JSON commun en alternative aux variables
  d'environnement.

## Non prévu

- Transport autre que stdio (SSE, HTTP) : le périmètre reste des serveurs MCP
  locaux simples, sans dépendance.
