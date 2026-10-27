; ============================================================================
;  SERVEUR MCP - Database (PureBasic Console / Stdio)
;  Exploration SQL en lecture seule : SQLite (integre) + PostgreSQL (optionnel)
; ============================================================================
;  Compilation : build.bat / build.sh
;  Transport   : JSON-RPC 2.0 sur stdin / stdout (delimite par \n)
;  Config      : MCP_DB_PATH           = fichier SQLite (defaut: database.db)
;                MCP_DB_POSTGRES_DSN   = chaine de connexion PostgreSQL
;                MCP_DB_ALLOW_WRITE=1  = autorise INSERT/UPDATE/DELETE/DDL
; ============================================================================

EnableExplicit

IncludeFile "../mcp_common/stdio.pbi"
IncludeFile "../mcp_common/logging.pbi"
IncludeFile "../mcp_common/json_helpers.pbi"
IncludeFile "../mcp_common/protocol.pbi"
IncludeFile "../mcp_common/jsonrpc.pbi"

IncludeFile "db_core.pbi"

; ---------------------------------------------------------------------------
; Programme principal
; ---------------------------------------------------------------------------
G_ServerName = "DatabaseMCPServer-PureBasic"
G_ServerVersion = "1.0.1"

If Not CheckStdio()
  End 1
EndIf

; IMPORTANT (PureBasic 6.41) : un seul driver de base peut etre utilise de
; maniere fiable par processus (le dernier Use* appele definit le driver
; actif, et l'autre moteur echoue silencieusement). dbMCP choisit donc UN
; moteur au demarrage : PostgreSQL si MCP_DB_POSTGRES_DSN est defini,
; sinon SQLite (comportement par defaut inchange).
Global G_PGEnv.s = GetEnvironmentVariable("MCP_DB_POSTGRES_DSN")

If G_PGEnv <> ""
  UsePostgreSQLDatabase()
  If DbOpenPostgres(G_PGEnv)
    LogDebug("PostgreSQL connecte : " + G_PGEnv)
  Else
    LogError("Connexion PostgreSQL impossible : " + DatabaseError())
    End 1
  EndIf
Else
  Global G_DBPath.s = GetEnvironmentVariable("MCP_DB_PATH")
  If G_DBPath = ""
    G_DBPath = "database.db"
  EndIf
  If Not DbOpenSQLite(G_DBPath)
    LogError("Impossible d'ouvrir la base SQLite : " + G_DBPath + " (" + DatabaseError() + ")")
    End 1
  EndIf
  LogDebug("SQLite ouverte : " + G_DBPath)
EndIf

If GetEnvironmentVariable("MCP_DB_ALLOW_WRITE") = "1"
  G_DBAllowWrite = #True
  LogDebug("Mode ecriture active (MCP_DB_ALLOW_WRITE=1)")
EndIf

*G_ToolHandler = @DbDispatch()
*G_CatalogBuilder = @DbBuildCatalog()

MCPMainLoop()

DbClose()

End
