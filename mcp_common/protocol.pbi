; ============================================================================
;  protocol.pbi - Reponses MCP standardisees (initialize)
;  Declare l'identite du serveur : chaque serveur renseigne ces globals
;  avant d'appeler MCPMainLoop() (voir jsonrpc.pbi).
; ============================================================================
;  A inclure avant jsonrpc.pbi :
;    IncludeFile "../mcp_common/protocol.pbi"
; ============================================================================

Global G_ServerName.s = "MCP-PB-Server"
Global G_ServerVersion.s = "1.0.0"

; Remplit l'objet "result" d'une reponse "initialize", conforme au
; protocole MCP (protocolVersion 2024-11-05, capacites, serverInfo).
Procedure BuildInitializeResponse(ResultObj.i)
  SetJSONString(AddJSONMember(ResultObj, "protocolVersion"), "2024-11-05")
  Protected Caps.i = AddJSONMember(ResultObj, "capabilities")
  SetJSONObject(Caps)
  SetJSONObject(AddJSONMember(Caps, "tools"))
  Protected ServerInfo.i = AddJSONMember(ResultObj, "serverInfo")
  SetJSONObject(ServerInfo)
  SetJSONString(AddJSONMember(ServerInfo, "name"), G_ServerName)
  SetJSONString(AddJSONMember(ServerInfo, "version"), G_ServerVersion)
EndProcedure
