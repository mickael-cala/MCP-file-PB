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
IncludeFile "../mcp_common/net_guard.pbi" ; classification reseau
IncludeFile "../mcp_common/logging.pbi"   ; requis par http.pbi (LogError)
IncludeFile "../mcp_common/http.pbi"      ; HttpHeaderValue (en-tetes)
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
; http : extraction d'un en-tete (CRLF WinHTTP / LF curl)
; ---------------------------------------------------------------------------
Procedure TestHttpHeaderValue()
  Protected Crlf.s = "HTTP/1.1 302 Found" + #CRLF$ + "Location: /a" + #CRLF$ + "Server: x" + #CRLF$
  Protected Lf.s   = "HTTP/2 302 " + #LF$ + "location: /b" + #LF$ + "server: y" + #LF$
  UTAssertStr("/a", HttpHeaderValue(Crlf, "location"), "en-tete CRLF")
  UTAssertStr("/b", HttpHeaderValue(Lf, "location"), "en-tete LF (curl)")
  UTAssertStr("", HttpHeaderValue(Lf, "absent"), "en-tete absent -> vide")
  UTAssertStr("x", HttpHeaderValue(Crlf, "server"), "en-tete insensible a la casse")
EndProcedure

; ---------------------------------------------------------------------------
; net_guard : classification IPv4 (fonctions pures, sans DNS)
; ---------------------------------------------------------------------------
Procedure TestNetGuardIPv4()
  UTAssert(#False, NetGuardIPv4IsGlobal(127, 0, 0, 1), "127.0.0.1 prive")
  UTAssert(#False, NetGuardIPv4IsGlobal(10, 1, 2, 3), "10/8 prive")
  UTAssert(#False, NetGuardIPv4IsGlobal(172, 20, 1, 1), "172.16/12 prive")
  UTAssert(#True,  NetGuardIPv4IsGlobal(172, 32, 1, 1), "172.32 public")
  UTAssert(#False, NetGuardIPv4IsGlobal(192, 168, 1, 1), "192.168/16 prive")
  UTAssert(#False, NetGuardIPv4IsGlobal(169, 254, 169, 254), "169.254/16 link-local")
  UTAssert(#False, NetGuardIPv4IsGlobal(100, 64, 0, 1), "100.64/10 CGNAT")
  UTAssert(#False, NetGuardIPv4IsGlobal(198, 51, 100, 1), "TEST-NET-2 prive")
  UTAssert(#False, NetGuardIPv4IsGlobal(203, 0, 113, 5), "TEST-NET-3 prive")
  UTAssert(#False, NetGuardIPv4IsGlobal(224, 0, 0, 1), "multicast prive")
  UTAssert(#False, NetGuardIPv4IsGlobal(0, 0, 0, 0), "unspecified prive")
  UTAssert(#True,  NetGuardIPv4IsGlobal(8, 8, 8, 8), "8.8.8.8 public")
  UTAssert(#True,  NetGuardIPv4IsGlobal(1, 1, 1, 1), "1.1.1.1 public")
  UTAssert(#True,  NetGuardIPv4IsGlobal(93, 184, 216, 34), "example.com public")
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
TestNetGuardIPv4()
TestHttpHeaderValue()

UTFinalize()

End
