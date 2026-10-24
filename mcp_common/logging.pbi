; ============================================================================
;  logging.pbi - Journalisation sur stderr pour les serveurs MCP
;  Depend de stdio.pbi (SendStderrLine). Jamais sur stdout : le flux MCP
;  ne doit contenir que du JSON-RPC.
; ============================================================================
;  A inclure apres stdio.pbi :
;    IncludeFile "../mcp_common/stdio.pbi"
;    IncludeFile "../mcp_common/logging.pbi"
; ============================================================================

Procedure LogLine(Level.s, Msg.s)
  SendStderrLine("[" + FormatDate("%HH:%II:%SS", Date()) + "] [" + Level + "] " + Msg)
EndProcedure

Procedure LogDebug(Msg.s)
  LogLine("DEBUG", Msg)
EndProcedure

Procedure LogError(Msg.s)
  LogLine("ERROR", Msg)
EndProcedure
