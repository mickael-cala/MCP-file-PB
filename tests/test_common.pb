; ============================================================================
;  test_common.pb - Tests unitaires des modules communs mcp_common/
;  Couvre : json_helpers (arguments, proprietes), DetectIsError.
; ============================================================================
;  Compilation : lance par tests/run_all.bat / run_all.sh (ou manuellement)
; ============================================================================

EnableExplicit

IncludeFile "../mcp_common/stdio.pbi"
IncludeFile "../mcp_common/json_helpers.pbi"
IncludeFile "../mcp_common/protocol.pbi"
IncludeFile "../mcp_common/jsonrpc.pbi"  ; DetectIsError
IncludeFile "../tests/unit_test.pbi"

; ---------------------------------------------------------------------------
; GetArgString / GetArgInt / GetArgBool
; ---------------------------------------------------------------------------
Procedure TestGetArgs()
  Protected J.i = ParseJSON(#PB_Any, ~"{\"s\":\"bonjour\",\"n\":42,\"b\":true,\"bn\":1}")
  Protected Args.i = JSONValue(J)

  UTAssertStr("bonjour", GetArgString(Args, "s"), "GetArgString lit une chaine")
  UTAssertStr("", GetArgString(Args, "absent"), "GetArgString cle absente -> vide")
  UTAssertStr("", GetArgString(#Null, "s"), "GetArgString objet nul -> vide")

  UTAssert(42, GetArgInt(Args, "n", -1), "GetArgInt lit un entier")
  UTAssert(-1, GetArgInt(Args, "absent", -1), "GetArgInt cle absente -> defaut")
  UTAssert(-1, GetArgInt(#Null, "n", -1), "GetArgInt objet nul -> defaut")

  UTAssert(1, GetArgBool(Args, "b", 0), "GetArgBool lit un booleen vrai")
  UTAssert(1, GetArgBool(Args, "bn", 0), "GetArgBool accepte un nombre non nul")
  UTAssert(0, GetArgBool(Args, "absent", 0), "GetArgBool cle absente -> defaut")

  FreeJSON(J)
EndProcedure

; ---------------------------------------------------------------------------
; DetectIsError
; ---------------------------------------------------------------------------
Procedure TestDetectIsError()
  UTAssert(1, DetectIsError("ACCES_REFUSE"), "ACCES_REFUSE est une erreur")
  UTAssert(1, DetectIsError("Erreur : fichier illisible"), "prefixe Erreur detecte")
  UTAssert(1, DetectIsError("ERREUR: URL invalide"), "prefixe ERREUR detecte")
  UTAssert(1, DetectIsError("Impossible d'ouvrir le fichier"), "prefixe Impossible detecte")
  UTAssert(1, DetectIsError("Echec du deplacement"), "prefixe Echec detecte")
  UTAssert(1, DetectIsError("Fichier introuvable : x"), "introuvable detecte")
  UTAssert(1, DetectIsError("Modification refusee : secret invalide"), "refusee detecte")
  UTAssert(1, DetectIsError("Fichier depasse la limite de 5 Mo."), "depasse detecte")

  UTAssert(0, DetectIsError("Fichier ecrit avec succes (12 octets)"), "succes non detecte")
  UTAssert(0, DetectIsError("Repertoire cree : /tmp/x"), "creation non detectee")
  UTAssert(0, DetectIsError("pong"), "reponse neutre non detectee")
EndProcedure

; ---------------------------------------------------------------------------
; AddProp* / ToolDef : construction de schéma
; ---------------------------------------------------------------------------
Procedure TestSchemaBuilders()
  Protected J.i = CreateJSON(#PB_Any)
  Protected Root.i = SetJSONObject(JSONValue(J))
  Protected ToolsArr.i = AddJSONMember(Root, "tools")
  SetJSONArray(ToolsArr)

  ToolDef(ToolsArr, "demo", "Outil de demo.", "a|string|Parametre A;b|integer|Parametre B", "a")

  Protected Out.s = ComposeJSON(J)
  UTAssertContains(Out, "demo", "ToolDef: nom present")
  UTAssertContains(Out, "Parametre A", "ToolDef: description presente")
  UTAssertContains(Out, "integer", "ToolDef: type integer present")
  UTAssertContains(Out, "required", "ToolDef: bloc required present")

  FreeJSON(J)
EndProcedure

; ---------------------------------------------------------------------------
; Programme principal
; -------------------------------------------------------------------
If Not CheckStdio()
  End 1
EndIf

TestGetArgs()
TestDetectIsError()
TestSchemaBuilders()

UTFinalize()

End
