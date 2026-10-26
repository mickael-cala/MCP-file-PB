; ============================================================================
;  jsonrpc.pbi - Noyau JSON-RPC 2.0 / boucle MCP generique
;  Depend de stdio.pbi, json_helpers.pbi et protocol.pbi.
; ============================================================================
;  Chaque serveur configure les globals ci-dessous, puis appelle MCPMainLoop() :
;
;    G_ServerName    = "MonServeurMCP-PureBasic"
;    G_ServerVersion = "1.0.0"
;    *G_ToolHandler    = @MonDispatch()       ; Prototype MCPToolHandler
;    *G_CatalogBuilder = @MonBuildCatalog()   ; Prototype MCPCatalogBuilder
;    ...
;    MCPMainLoop()
; ============================================================================

; ---------------------------------------------------------------------------
; Hooks configures par le serveur
; ---------------------------------------------------------------------------
; Dispatch d'un outil : retourne le texte de resultat ; *IsError\i = #True
; si l'appel doit etre marque isError dans la reponse MCP.
Prototype.s MCPToolHandler(ToolName.s, ArgsObj.i, *IsError.Integer)
; Construit et retourne un handle JSON du catalogue : {"tools": [...]}
Prototype.i MCPCatalogBuilder()

Global *G_ToolHandler.MCPToolHandler = #Null
Global *G_CatalogBuilder.MCPCatalogBuilder = #Null

; ---------------------------------------------------------------------------
; Emission des reponses
; ---------------------------------------------------------------------------
Procedure SendResponse(RespJSON.i)
  Protected Out.s = ComposeJSON(RespJSON)
  SendRawLine(Out)
  FreeJSON(RespJSON)
EndProcedure

Procedure SendRawError(IdValue.i, Code.i, Msg.s)
  Protected J.i = CreateJSON(#PB_Any)
  Protected Root.i = SetJSONObject(JSONValue(J))
  SetJSONString(AddJSONMember(Root, "jsonrpc"), "2.0")
  If IdValue
    Protected IdMember.i = AddJSONMember(Root, "id")
    If JSONType(IdValue) = #PB_JSON_String
      SetJSONString(IdMember, GetJSONString(IdValue))
    ElseIf JSONType(IdValue) = #PB_JSON_Number
      SetJSONDouble(IdMember, GetJSONDouble(IdValue))
    Else
      SetJSONNull(IdMember)
    EndIf
  Else
    SetJSONNull(AddJSONMember(Root, "id"))
  EndIf
  Protected ErrObj.i = AddJSONMember(Root, "error")
  SetJSONObject(ErrObj)
  SetJSONInteger(AddJSONMember(ErrObj, "code"), Code)
  SetJSONString(AddJSONMember(ErrObj, "message"), Msg)
  SendResponse(J)
EndProcedure

Procedure AttachResultPayload(ResultObj.i, ContentText.s, IsError.i)
  Protected ContentArr.i = AddJSONMember(ResultObj, "content")
  SetJSONArray(ContentArr)
  Protected ItemObj.i = AddJSONElement(ContentArr)
  SetJSONObject(ItemObj)
  SetJSONString(AddJSONMember(ItemObj, "type"), "text")
  SetJSONString(AddJSONMember(ItemObj, "text"), ContentText)
  SetJSONBoolean(AddJSONMember(ResultObj, "isError"), IsError)
EndProcedure

; ---------------------------------------------------------------------------
; Heuristique d'erreur : un message d'echec d'outil doit commencer par (ou
; contenir) un de ces marqueurs pour que isError soit positionne. Les outils
; peuvent aussi lever *IsError\i directement dans le dispatch.
; ---------------------------------------------------------------------------
Procedure.i DetectIsError(OutputStr.s)
  ; Heuristique de DERNIER RECOURS uniquement : premiere ligne, courte, pour ne
  ; jamais inspecter un payload de resultat (JSON, listing, contenu de fichier).
  Protected FirstLine.s = OutputStr
  Protected NL.i = FindString(FirstLine, #LF$)
  If NL > 0 : FirstLine = Left(FirstLine, NL - 1) : EndIf
  If Len(FirstLine) > 300 : FirstLine = Left(FirstLine, 300) : EndIf

  If FirstLine = "ACCES_REFUSE"
    ProcedureReturn #True
  EndIf
  If FindString(FirstLine, "Erreur") = 1 Or FindString(FirstLine, "ERREUR") = 1 Or FindString(FirstLine, "Impossible") = 1 Or FindString(FirstLine, "Echec") = 1
    ProcedureReturn #True
  EndIf
  If FindString(FirstLine, "introuvable") > 0 Or FindString(FirstLine, "refusee") > 0 Or FindString(FirstLine, "depasse") > 0
    ProcedureReturn #True
  EndIf
  ProcedureReturn #False
EndProcedure

; ---------------------------------------------------------------------------
; Traitement generique d'une requete JSON-RPC (une ligne)
; ---------------------------------------------------------------------------
Procedure ProcessRequest(Line.s)
  Protected ReqJSON.i = ParseJSON(#PB_Any, Line)
  If Not ReqJSON
    SendRawError(#Null, -32700, "Parse error: invalid JSON")
    ProcedureReturn
  EndIf

  Protected RootVal.i = JSONValue(ReqJSON)
  If JSONType(RootVal) <> #PB_JSON_Object
    FreeJSON(ReqJSON)
    SendRawError(#Null, -32600, "Invalid Request: Root must be an object")
    ProcedureReturn
  EndIf

  Protected MethodMember.i = GetJSONMember(RootVal, "method")
  Protected Method.s = ""
  If MethodMember And JSONType(MethodMember) = #PB_JSON_String
    Method = GetJSONString(MethodMember)
  EndIf

  Protected IdMember.i = GetJSONMember(RootVal, "id")

  ; Une requete sans "method" textuelle n'est pas un objet Request valide.
  If Method = ""
    FreeJSON(ReqJSON)
    SendRawError(#Null, -32600, "Invalid Request: missing method")
    ProcedureReturn
  EndIf

  ; JSON-RPC 2.0 : toute requete SANS "id" est une notification. Aucune reponse
  ; ne doit etre emise, quelle que soit l'issue du traitement (y compris
  ; notifications/initialized, tools/list et tools/call).
  If IdMember = 0
    FreeJSON(ReqJSON)
    ProcedureReturn
  EndIf

  ; Cas particulier tools/list : emission directe du catalogue compose
  If Method = "tools/list"
    Protected CatalogJSON.i = #Null
    If *G_CatalogBuilder
      CatalogJSON = *G_CatalogBuilder()
    EndIf

    Protected IdValStr.s = "null"
    If IdMember
      If JSONType(IdMember) = #PB_JSON_String
        Protected IdRaw.s = GetJSONString(IdMember)
        IdRaw = ReplaceString(IdRaw, Chr(92), Chr(92) + Chr(92))
        IdRaw = ReplaceString(IdRaw, Chr(34), Chr(92) + Chr(34))
        IdValStr = Chr(34) + IdRaw + Chr(34)
      ElseIf JSONType(IdMember) = #PB_JSON_Number
        IdValStr = Str(GetJSONInteger(IdMember))
      EndIf
    EndIf

    If CatalogJSON
      ; Reponse conforme JSON-RPC : le catalogue est compose en un seul objet
      ; "result" puis envoye sur une ligne (protocole stdio delimite par \n).
      Protected Body.s = ComposeJSON(CatalogJSON)
      SendRawLine(Chr(123) + Chr(34) + "jsonrpc" + Chr(34) + ":" + Chr(34) + "2.0" + Chr(34) + "," + Chr(34) + "id" + Chr(34) + ":" + IdValStr + "," + Chr(34) + "result" + Chr(34) + ":" + Body + Chr(125))
      FreeJSON(CatalogJSON)
    Else
      SendRawError(IdMember, -32603, "Erreur : catalogue d'outils non configure")
    EndIf
    FreeJSON(ReqJSON)
    ProcedureReturn
  EndIf

  ; Creation de la reponse JSON-RPC standard
  Protected RespJSON.i = CreateJSON(#PB_Any)
  Protected RespRoot.i = SetJSONObject(JSONValue(RespJSON))
  SetJSONString(AddJSONMember(RespRoot, "jsonrpc"), "2.0")

  Protected ResId.i = AddJSONMember(RespRoot, "id")
  If IdMember
    If JSONType(IdMember) = #PB_JSON_String
      SetJSONString(ResId, GetJSONString(IdMember))
    ElseIf JSONType(IdMember) = #PB_JSON_Number
      SetJSONDouble(ResId, GetJSONDouble(IdMember))
    Else
      SetJSONNull(ResId)
    EndIf
  Else
    SetJSONNull(ResId)
  EndIf

  Protected ResultObj.i = AddJSONMember(RespRoot, "result")
  SetJSONObject(ResultObj)

  Select Method
    Case "initialize"
      BuildInitializeResponse(ResultObj)

    Case "tools/call"
      Protected ParamsMember.i = GetJSONMember(RootVal, "params")
      Protected ToolName.s = ""
      Protected ArgsMember.i = #Null
      If ParamsMember And JSONType(ParamsMember) = #PB_JSON_Object
        ToolName = GetArgString(ParamsMember, "name")
        ArgsMember = GetJSONMember(ParamsMember, "arguments")
      EndIf

      ; Parametres invalides : erreur JSON-RPC normalisee (-32602).
      If ToolName = ""
        FreeJSON(RespJSON)
        SendRawError(IdMember, -32602, "Invalid params: missing tool name")
        FreeJSON(ReqJSON)
        ProcedureReturn
      EndIf

      Protected OutputStr.s = ""
      Protected IsErr.i = #False
      ToolStateReset()
      If *G_ToolHandler
        OutputStr = *G_ToolHandler(ToolName, ArgsMember, @IsErr)
      Else
        OutputStr = "Erreur : aucun gestionnaire d'outils configure."
        IsErr = #True
      EndIf

      If OutputStr = "ACCES_REFUSE"
        OutputStr = "Erreur : Acces refuse en dehors de la zone autorisee."
      EndIf

      ; Priorite a l'etat explicite fourni par l'outil ; heuristique seulement
      ; si l'outil n'a rien declare.
      If G_ToolState < 0
        IsErr = #True
      ElseIf G_ToolState > 0
        IsErr = #False
      ElseIf Not IsErr And DetectIsError(OutputStr)
        IsErr = #True
      EndIf

      AttachResultPayload(ResultObj, OutputStr, IsErr)

    Default
      ; Methode inconnue : erreur JSON-RPC normalisee
      FreeJSON(RespJSON)
      SendRawError(IdMember, -32601, "Method not found")
      FreeJSON(ReqJSON)
      ProcedureReturn
  EndSelect

  SendResponse(RespJSON)
  FreeJSON(ReqJSON)
EndProcedure

; ---------------------------------------------------------------------------
; Boucle principale : lit stdin jusqu'a EOF, puis sort proprement
; ---------------------------------------------------------------------------
Procedure MCPMainLoop()
  Define Line.s

  While #True
    Line = ReadStdinLine()
    If Line = "" And G_EOF
      Break                      ; EOF stdin -> sortie propre du serveur
    EndIf
    Line = Trim(Line)
    If Line <> ""
      ProcessRequest(Line)
    EndIf
  Wend
EndProcedure
