; ============================================================================
;  SERVEUR MCP - GitHub (PureBasic Console / Stdio)
;  API REST GitHub v3 : repos, issues, pull requests, commits, recherches
; ============================================================================
;  Compilation : build.bat / build.sh
;  Transport   : JSON-RPC 2.0 sur stdin / stdout (delimite par \n)
;  Config      : MCP_GITHUB_TOKEN    = token PAT (requis)
;                MCP_GITHUB_API_BASE = base API (defaut https://api.github.com)
; ============================================================================

EnableExplicit

IncludeFile "../mcp_common/stdio.pbi"
IncludeFile "../mcp_common/logging.pbi"
IncludeFile "../mcp_common/json_helpers.pbi"
IncludeFile "../mcp_common/http.pbi"
IncludeFile "../mcp_common/protocol.pbi"
IncludeFile "../mcp_common/jsonrpc.pbi"

IncludeFile "github_core.pbi"

; ---------------------------------------------------------------------------
; Programme principal
; ---------------------------------------------------------------------------
G_ServerName = "GitHubMCPServer-PureBasic"
G_ServerVersion = "1.0.0"

If Not CheckStdio()
  End 1
EndIf

G_GhToken = GetEnvironmentVariable("MCP_GITHUB_TOKEN")
If G_GhToken = ""
  LogError("MCP_GITHUB_TOKEN non configure : les outils retourneront une erreur explicite.")
Else
  LogDebug("Token GitHub charge (longueur " + Str(Len(G_GhToken)) + ").")
EndIf

Global G_GhApiBaseEnv.s = GetEnvironmentVariable("MCP_GITHUB_API_BASE")
If G_GhApiBaseEnv <> ""
  G_GhApiBase = G_GhApiBaseEnv
EndIf
LogDebug("API GitHub : " + G_GhApiBase)

*G_ToolHandler = @GhDispatch()
*G_CatalogBuilder = @GhBuildCatalog()

MCPMainLoop()

End
