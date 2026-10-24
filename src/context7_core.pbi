; ============================================================================
;  context7_core.pbi - Coeur metier du serveur MCP Context7
;  Resolution de bibliotheques + documentation via l'API context7.com.
;  Inclus par src/context7MCP.pb et tests/test_context7.pb.
; ============================================================================
;  API reelle (verifiee) :
;    GET https://context7.com/api/v1/search?query=X&libraryType=oss
;        -> {"results":[{"id":"/owner/repo","title":...,"description":...}]}
;    GET https://context7.com/api/v1/docs?libraryId=X&query=Y&tokens=N&topic=T
;        -> {"content":"..."}   (exige une cle : Authorization: Bearer ctx7sk...)
;  Codes : 401 cle manquante/invalide, 429 quota, 5xx indisponible.
; ============================================================================

Global G_C7ApiKey.s = ""

; ---------------------------------------------------------------------------
; Encodage URL (composant de requete : tout sauf alphanum + -._~)
; ---------------------------------------------------------------------------
Procedure.s UrlEncodeComponent(S.s)
  Protected i.i, c.i, Out.s = "", Hex.s
  For i = 1 To Len(S)
    c = Asc(Mid(S, i, 1))
    If (c >= 48 And c <= 57) Or (c >= 65 And c <= 90) Or (c >= 97 And c <= 122) Or c = 45 Or c = 46 Or c = 95 Or c = 126
      Out + Chr(c)
    Else
      Hex = Hex(c)
      If Len(Hex) < 2 : Hex = "0" + Hex : EndIf
      Out + "%" + Hex
    EndIf
  Next
  ProcedureReturn Out
EndProcedure

; ---------------------------------------------------------------------------
; Couche HTTP GET avec en-tetes
; ---------------------------------------------------------------------------
CompilerIf #PB_Compiler_OS = #PB_OS_Windows

#WINHTTP_FLAG_SECURE = $00800000
#WINHTTP_QUERY_STATUS_CODE = 19
#WINHTTP_QUERY_FLAG_NUMBER = $20000000

PrototypeC whttpOpen(lpszAgent.s, dwAccessType.i, lpszProxyName.i, lpszProxyBypass.i, dwFlags.i)
PrototypeC whttpConnect(hSession.i, pswzServerName.s, nServerPort.i, dwReserved.i)
PrototypeC whttpOpenRequest(hConnect.i, pwszVerb.s, pwszObjectName.s, pwszVersion.i, pwszReferrer.i, plpszAcceptTypes.i, dwFlagsAndAttributes.i)
PrototypeC whttpAddRequestHeaders(hRequest.i, pwszHeaders.s, dwHeadersLength.i, dwModifiers.i)
PrototypeC whttpSendRequest(hRequest.i, pwszHeaders.i, dwHeadersLength.i, lpOptional.i, dwOptionalLength.i, dwTotalLength.i, dwContext.i)
PrototypeC whttpReceiveResponse(hRequest.i, lpReserved.i)
PrototypeC whttpQueryHeaders(hRequest.i, dwInfoLevel.i, pwszName.i, lpBuffer.i, lpdwBufferLength.i, lpdwIndex.i)
PrototypeC whttpQueryDataAvailable(hRequest.i, lpdwNumberOfBytesAvailable.i)
PrototypeC whttpReadData(hRequest.i, lpBuffer.i, dwNumberOfBytesToRead.i, lpdwNumberOfBytesRead.i)
PrototypeC whttpCloseHandle(hInternet.i)

Global hWinHTTP.i = 0
Global whttp_WinHttpOpen.whttpOpen
Global whttp_WinHttpConnect.whttpConnect
Global whttp_WinHttpOpenRequest.whttpOpenRequest
Global whttp_WinHttpAddRequestHeaders.whttpAddRequestHeaders
Global whttp_WinHttpSendRequest.whttpSendRequest
Global whttp_WinHttpReceiveResponse.whttpReceiveResponse
Global whttp_WinHttpQueryHeaders.whttpQueryHeaders
Global whttp_WinHttpQueryDataAvailable.whttpQueryDataAvailable
Global whttp_WinHttpReadData.whttpReadData
Global whttp_WinHttpCloseHandle.whttpCloseHandle

Procedure.i C7HttpInit()
  If hWinHTTP : ProcedureReturn #True : EndIf
  hWinHTTP = OpenLibrary(#PB_Any, "winhttp.dll")
  If hWinHTTP = 0 : ProcedureReturn #False : EndIf
  whttp_WinHttpOpen             = GetFunction(hWinHTTP, "WinHttpOpen")
  whttp_WinHttpConnect          = GetFunction(hWinHTTP, "WinHttpConnect")
  whttp_WinHttpOpenRequest      = GetFunction(hWinHTTP, "WinHttpOpenRequest")
  whttp_WinHttpAddRequestHeaders= GetFunction(hWinHTTP, "WinHttpAddRequestHeaders")
  whttp_WinHttpSendRequest      = GetFunction(hWinHTTP, "WinHttpSendRequest")
  whttp_WinHttpReceiveResponse  = GetFunction(hWinHTTP, "WinHttpReceiveResponse")
  whttp_WinHttpQueryHeaders     = GetFunction(hWinHTTP, "WinHttpQueryHeaders")
  whttp_WinHttpQueryDataAvailable = GetFunction(hWinHTTP, "WinHttpQueryDataAvailable")
  whttp_WinHttpReadData         = GetFunction(hWinHTTP, "WinHttpReadData")
  whttp_WinHttpCloseHandle      = GetFunction(hWinHTTP, "WinHttpCloseHandle")
  If whttp_WinHttpOpen = 0 Or whttp_WinHttpSendRequest = 0 Or whttp_WinHttpReadData = 0
    ProcedureReturn #False
  EndIf
  ProcedureReturn #True
EndProcedure

; GET HTTPS avec en-tete Authorization optionnelle.
; Retourne le corps ; *Status\i recoit le code HTTP (ou -1 en cas d'echec reseau).
Procedure.s C7HttpGet(Url.s, AuthHeader.s, TimeoutSec.i, *Status.Integer)
  *Status\i = -1
  If Not C7HttpInit() : ProcedureReturn "" : EndIf

  Protected Server.s = GetURLPart(Url, #PB_URL_Site)
  If Server = "" : ProcedureReturn "" : EndIf
  Protected Port.i = Val(GetURLPart(Url, #PB_URL_Port))
  If Port = 0 : Port = 443 : EndIf
  Protected Path.s = GetURLPart(Url, #PB_URL_Path)
  Protected Params.s = GetURLPart(Url, #PB_URL_Parameters)
  If Params <> "" : Path + "?" + Params : EndIf
  If Path = "" : Path = "/" : EndIf

  Protected hSession.i = whttp_WinHttpOpen("MCP-Context7-PureBasic/1.0", 0, 0, 0, 0)
  If hSession = 0 : ProcedureReturn "" : EndIf
  Protected hConnect.i = whttp_WinHttpConnect(hSession, Server, Port, 0)
  If hConnect = 0 : whttp_WinHttpCloseHandle(hSession) : ProcedureReturn "" : EndIf
  Protected hRequest.i = whttp_WinHttpOpenRequest(hConnect, "GET", Path, 0, 0, 0, #WINHTTP_FLAG_SECURE)
  If hRequest = 0
    whttp_WinHttpCloseHandle(hConnect) : whttp_WinHttpCloseHandle(hSession)
    ProcedureReturn ""
  EndIf

  ; Timeout (ms) : resolver, connect, send-receive
  ; (WinHttpSetTimeouts non importe : le delai global reste gere par l'appelant)

  If AuthHeader <> ""
    If whttp_WinHttpAddRequestHeaders(hRequest, AuthHeader, -1, 0) = 0
      LogError("WinHttpAddRequestHeaders a echoue")
    EndIf
  EndIf

  If whttp_WinHttpSendRequest(hRequest, 0, 0, 0, 0, 0, 0) = 0
    whttp_WinHttpCloseHandle(hRequest) : whttp_WinHttpCloseHandle(hConnect) : whttp_WinHttpCloseHandle(hSession)
    ProcedureReturn ""
  EndIf
  If whttp_WinHttpReceiveResponse(hRequest, 0) = 0
    whttp_WinHttpCloseHandle(hRequest) : whttp_WinHttpCloseHandle(hConnect) : whttp_WinHttpCloseHandle(hSession)
    ProcedureReturn ""
  EndIf

  ; Code de statut
  Protected Code.i = 0, CodeLen.i = 4
  If whttp_WinHttpQueryHeaders(hRequest, #WINHTTP_QUERY_STATUS_CODE | #WINHTTP_QUERY_FLAG_NUMBER, 0, @Code, @CodeLen, 0)
    *Status\i = Code
  EndIf

  ; Corps de la reponse
  Protected *Buf = AllocateMemory(65536)
  Protected Body.s = "", Avail.i = 0, ReadLow.i = 0
  If *Buf
    While whttp_WinHttpQueryDataAvailable(hRequest, @Avail)
      If Avail <= 0 : Break : EndIf
      If Avail > 65536 : Avail = 65536 : EndIf
      ReadLow = 0
      If whttp_WinHttpReadData(hRequest, *Buf, Avail, @ReadLow) = 0 Or ReadLow <= 0
        Break
      EndIf
      Body + PeekS(*Buf, ReadLow, #PB_UTF8 | #PB_ByteLength)
    Wend
    FreeMemory(*Buf)
  EndIf

  whttp_WinHttpCloseHandle(hRequest)
  whttp_WinHttpCloseHandle(hConnect)
  whttp_WinHttpCloseHandle(hSession)
  ProcedureReturn Body
EndProcedure

CompilerElse

; Fallback Linux/macOS : HTTP integre PureBasic (pas d'en-tete Authorization
; possible -> l'appel avec cle est rejete proprement, voir ToolQueryDocs).
Procedure.s C7HttpGet(Url.s, AuthHeader.s, TimeoutSec.i, *Status.Integer)
  If AuthHeader <> ""
    *Status\i = -2   ; marqueur : en-tetes non supportes sur cet OS
    ProcedureReturn ""
  EndIf
  HTTPTimeout(TimeoutSec * 1000)
  Protected Req.i = HTTPRequestMemory(#PB_HTTP_Get, Url)
  If Not Req
    *Status\i = -1
    ProcedureReturn ""
  EndIf
  *Status\i = Val(HTTPInfo(Req, #PB_HTTP_StatusCode))
  Protected Result.s = ""
  Protected *Buf = HTTPMemory(Req)
  If *Buf
    Protected Size.i = MemorySize(*Buf)
    If Size > 0
      Result = PeekS(*Buf, Size, #PB_UTF8 | #PB_ByteLength)
    EndIf
  EndIf
  FinishHTTP(Req)
  ProcedureReturn Result
EndProcedure

CompilerEndIf

; ---------------------------------------------------------------------------
; Mapping des erreurs HTTP en message MCP
; ---------------------------------------------------------------------------
Procedure.s C7HttpErrorText(Status.i, Prefix.s)
  Select Status
    Case -2
      ProcedureReturn Prefix + " : l'en-tete Authorization n'est pas supportee sur cet OS (HTTP integre sans en-tetes). Cles API : Windows requis."
    Case -1
      ProcedureReturn Prefix + " : echec reseau (DNS, connexion ou timeout)."
    Case 401
      ProcedureReturn Prefix + " : cle API invalide ou manquante (401). Verifier MCP_CONTEXT7_API_KEY (prefixe ctx7sk)."
    Case 403
      ProcedureReturn Prefix + " : acces refuse (403)."
    Case 404
      ProcedureReturn Prefix + " : introuvable (404)."
    Case 429
      ProcedureReturn Prefix + " : quota depasse (429), reessayer dans quelques instants."
    Default
      If Status >= 500
        ProcedureReturn Prefix + " : Context7 indisponible (" + Str(Status) + ")."
      ElseIf Status <> 200
        ProcedureReturn Prefix + " : erreur HTTP " + Str(Status) + "."
      EndIf
  EndSelect
  ProcedureReturn ""
EndProcedure

; ---------------------------------------------------------------------------
; Outils MCP
; ---------------------------------------------------------------------------

; resolve_library_id : recherche de bibliotheques (fonctionne sans cle)
Procedure.s ToolResolveLibraryId(Query.s, LibraryType.s)
  If Trim(Query) = ""
    ProcedureReturn "Erreur : 'query' ne peut pas etre vide."
  EndIf
  If LibraryType = "" : LibraryType = "oss" : EndIf

  Protected Url.s = "https://context7.com/api/v1/search?query=" + UrlEncodeComponent(Query) + "&libraryType=" + UrlEncodeComponent(LibraryType)
  Protected Status.i
  Protected Body.s = C7HttpGet(Url, "", 15, @Status)
  If Status <> 200
    Protected Err.s = C7HttpErrorText(Status, "Erreur recherche")
    If Err <> "" : ProcedureReturn Err : EndIf
    ProcedureReturn "Erreur recherche : reponse vide (statut " + Str(Status) + ")."
  EndIf

  Protected J.i = ParseJSON(#PB_Any, Body)
  If J = 0
    ProcedureReturn "Erreur : reponse Context7 invalide (JSON illisible)."
  EndIf
  Protected Root.i = JSONValue(J)
  Protected Results.i = GetJSONMember(Root, "results")
  If Results = 0 Or JSONType(Results) <> #PB_JSON_Array
    FreeJSON(J)
    ProcedureReturn "Erreur : reponse Context7 invalide (pas de tableau 'results')."
  EndIf

  Protected n.i = JSONArraySize(Results)
  If n = 0
    FreeJSON(J)
    ProcedureReturn "Aucune bibliotheque trouvee pour '" + Query + "'."
  EndIf

  Protected Res.s = Str(n) + " bibliotheque(s) pour '" + Query + "' :" + #LF$
  Protected i.i
  For i = 0 To n - 1
    Protected Item.i = GetJSONElement(Results, i)
    Protected Id.s = GetArgString(Item, "id")
    Protected Title.s = GetArgString(Item, "title")
    Protected Descr.s = GetArgString(Item, "description")
    Res + Id + "  --  " + Title
    If Descr <> ""
      Res + "  --  " + Left(Descr, 120)
    EndIf
    Res + #LF$
  Next
  Res + "Utilisez query_docs avec l'id choisi (ex. /owner/repo)."
  FreeJSON(J)
  ProcedureReturn Res
EndProcedure

; query_docs : documentation d'une bibliotheque (cle API requise)
Procedure.s ToolQueryDocs(LibraryId.s, Query.s, Tokens.i, Topic.s, MaxLen.i)
  If Trim(LibraryId) = ""
    ProcedureReturn "Erreur : 'libraryId' est requis (ex. /reactjs/react.dev/latest)."
  EndIf
  If Tokens <= 0 : Tokens = 5000 : EndIf
  If MaxLen <= 0 : MaxLen = 10000 : EndIf

  ; Cle API requise : l'API renvoie un 400 trompeur ("invalid_format") sans
  ; en-tete Authorization -> on intercepte avant l'appel pour un message clair.
  If G_C7ApiKey = ""
    ProcedureReturn "Erreur : MCP_CONTEXT7_API_KEY non configure. Obtenez une cle sur https://context7.com (prefixe ctx7sk) puis relancez le serveur."
  EndIf

  Protected Auth.s = "Authorization: Bearer " + G_C7ApiKey

  Protected Url.s = "https://context7.com/api/v1/docs?libraryId=" + UrlEncodeComponent(LibraryId) +
                    "&query=" + UrlEncodeComponent(Query) +
                    "&tokens=" + Str(Tokens)
  If Topic <> ""
    Url + "&topic=" + UrlEncodeComponent(Topic)
  EndIf

  Protected Status.i
  Protected Body.s = C7HttpGet(Url, Auth, 20, @Status)
  If Status <> 200
    Protected Err.s = C7HttpErrorText(Status, "Erreur docs")
    If Err <> "" : ProcedureReturn Err : EndIf
    ProcedureReturn "Erreur docs : reponse vide (statut " + Str(Status) + ")."
  EndIf

  Protected J.i = ParseJSON(#PB_Any, Body)
  If J = 0
    ProcedureReturn "Erreur : reponse Context7 invalide (JSON illisible)."
  EndIf
  Protected Root.i = JSONValue(J)
  Protected Content.i = GetJSONMember(Root, "content")
  If Content = 0 Or JSONType(Content) <> #PB_JSON_String
    ; Erreur applicative JSON {"error":..., "message":...}
    Protected Msg.i = GetJSONMember(Root, "message")
    If Msg And JSONType(Msg) = #PB_JSON_String
      Protected AppMsg.s = GetJSONString(Msg)
      FreeJSON(J)
      ProcedureReturn "Erreur Context7 : " + AppMsg
    EndIf
    FreeJSON(J)
    ProcedureReturn "Erreur : reponse Context7 invalide (pas de 'content')."
  EndIf

  Protected Text.s = GetJSONString(Content)
  FreeJSON(J)

  ; Troncature locale max_length
  Protected TotalLen.i = Len(Text)
  Protected Out.s = Left(Text, MaxLen)
  If TotalLen > MaxLen
    Out + #LF$ + "[Contenu : " + Str(TotalLen) + " caracteres au total ; tronque a " + Str(MaxLen) + " ; augmentez 'tokens' ou affinez 'query']"
  EndIf
  ProcedureReturn Out
EndProcedure

; ---------------------------------------------------------------------------
; Catalogue MCP
; ---------------------------------------------------------------------------
Procedure.i C7BuildCatalog()
  Protected RootJSON.i = CreateJSON(#PB_Any)
  Protected RootVal.i = SetJSONObject(JSONValue(RootJSON))
  Protected ToolsArr.i = AddJSONMember(RootVal, "tools")
  SetJSONArray(ToolsArr)

  ToolDef(ToolsArr, "resolve_library_id", "Recherche une bibliotheque sur Context7 et retourne la liste des identifiants (/owner/repo).", "query|string|Nom ou description de la bibliotheque;libraryType|string|Filtre (defaut: oss)", "query")
  ToolDef(ToolsArr, "query_docs", "Retourne la documentation d'une bibliotheque Context7 (cle API MCP_CONTEXT7_API_KEY requise).", "libraryId|string|Identifiant /owner/repo[/tag];query|string|Sujet recherche;tokens|integer|Budget de tokens (defaut: 5000);topic|string|Filtre de topic (optionnel);max_length|integer|Troncature locale du texte retourne (defaut: 10000)", "libraryId;query")

  ProcedureReturn RootJSON
EndProcedure

; ---------------------------------------------------------------------------
; Dispatch des outils (hook *G_ToolHandler)
; ---------------------------------------------------------------------------
Procedure.s C7Dispatch(ToolName.s, ArgsObj.i, *IsError.Integer)
  Select ToolName
    Case "resolve_library_id"
      ProcedureReturn ToolResolveLibraryId(GetArgString(ArgsObj, "query"), GetArgString(ArgsObj, "libraryType"))
    Case "query_docs"
      ProcedureReturn ToolQueryDocs(GetArgString(ArgsObj, "libraryId"), GetArgString(ArgsObj, "query"), GetArgInt(ArgsObj, "tokens", 5000), GetArgString(ArgsObj, "topic"), GetArgInt(ArgsObj, "max_length", 10000))
    Default
      *IsError\i = #True
      ProcedureReturn "Outil inconnu : " + ToolName
  EndSelect
EndProcedure
