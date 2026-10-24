; ============================================================================
;  SERVEUR MCP - Fetch (PureBasic Console / Stdio)
;  Récupération de pages web + conversion HTML -> Markdown
; ============================================================================

EnableExplicit

; ---------------------------------------------------------------------------
; Couche E/S stdio (identique à fileMCP.pb / seqThinkingMCP.pb)
; ---------------------------------------------------------------------------
CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #C_STD_INPUT_HANDLE  = -10
  #C_STD_OUTPUT_HANDLE = -11

  PrototypeC protoGetStdHandle(nStdHandle.i)
  PrototypeC protoReadFile(hFile.i, *lpBuffer, nNumberOfBytesToRead.l, *lpNumberOfBytesRead, *lpOverlapped)
  PrototypeC protoWriteFile(hFile.i, *lpBuffer, nNumberOfBytesToWrite.l, *lpNumberOfBytesWritten, *lpOverlapped)
  PrototypeC protoFlushFileBuffers(hFile.i)

  Global hKernel32.i = OpenLibrary(#PB_Any, "kernel32.dll")
  Global Std_GetHandle.protoGetStdHandle         = GetFunction(hKernel32, "GetStdHandle")
  Global Std_ReadFile.protoReadFile              = GetFunction(hKernel32, "ReadFile")
  Global Std_WriteFile.protoWriteFile            = GetFunction(hKernel32, "WriteFile")
  Global Std_FlushBuffers.protoFlushFileBuffers  = GetFunction(hKernel32, "FlushFileBuffers")
CompilerEndIf

Procedure SendRawLine(Text.s)
  Protected OutText.s = Text + #LF$
  Protected Size.i = StringByteLength(OutText, #PB_UTF8)
  If Size = 0 : ProcedureReturn : EndIf
  Protected *Mem = AllocateMemory(Size)
  If *Mem
    PokeS(*Mem, OutText, -1, #PB_UTF8 | #PB_String_NoZero)
    CompilerIf #PB_Compiler_OS = #PB_OS_Windows
      Protected hOut.i = Std_GetHandle(#C_STD_OUTPUT_HANDLE)
      Protected WrittenLow.l = 0
      Std_WriteFile(hOut, *Mem, Size, @WrittenLow, #Null)
      Std_FlushBuffers(hOut)
    CompilerElse
      Protected Written.i = write_(1, *Mem, Size)
      fflush_(0)
    CompilerEndIf
    FreeMemory(*Mem)
  EndIf
EndProcedure

Global G_InBufSize.i = 65536
Global *G_InBuf      = AllocateMemory(G_InBufSize)
Global G_InDataLen.i = 0
Global G_InPos.i     = 0
Global G_EOF.i       = #False

Procedure.i FillInputBuffer()
  If G_InPos >= G_InDataLen
    CompilerIf #PB_Compiler_OS = #PB_OS_Windows
      Protected ReadLow.l = 0
      If Std_ReadFile(Std_GetHandle(#C_STD_INPUT_HANDLE), *G_InBuf, G_InBufSize, @ReadLow, #Null)
        G_InDataLen = ReadLow
      Else
        G_InDataLen = 0
      EndIf
    CompilerElse
      G_InDataLen = read_(0, *G_InBuf, G_InBufSize)
    CompilerEndIf
    G_InPos = 0
    If G_InDataLen <= 0
      G_EOF = #True
      ProcedureReturn #False
    EndIf
  EndIf
  ProcedureReturn #True
EndProcedure

Procedure.s ReadStdinLine()
  If Not FillInputBuffer()
    ProcedureReturn ""
  EndIf
  Protected Start.i = G_InPos
  Protected Found.i = #False
  While #True
    Protected i.i
    For i = G_InPos To G_InDataLen - 1
      If PeekB(*G_InBuf + i) = $0A
        G_InPos = i + 1
        Found = #True
        Break
      EndIf
    Next
    If Found : Break : EndIf
    Protected Remaining.i = G_InDataLen - G_InPos
    If Remaining > 0
      MoveMemory(*G_InBuf + G_InPos, *G_InBuf, Remaining)
    EndIf
    G_InDataLen = Remaining
    G_InPos = Remaining
    If Not FillInputBuffer()
      If G_InDataLen > G_InPos
        G_InPos = G_InDataLen
      EndIf
      Break
    EndIf
    If G_InDataLen >= G_InBufSize
      G_InPos = G_InDataLen
      Break
    EndIf
  Wend
  Protected Length.i = G_InPos - 1 - Start
  If Length < 0 : Length = 0 : EndIf
  If Length > 0 And PeekB(*G_InBuf + Start + Length - 1) = $0D
    Length - 1
  EndIf
  ProcedureReturn PeekS(*G_InBuf + Start, Length, #PB_UTF8 | #PB_ByteLength)
EndProcedure

; ---------------------------------------------------------------------------
; Validation d'URL et garde-fous de sécurité
; ---------------------------------------------------------------------------
Procedure.i IsPrivateHost(Host.s)
  ; Refuse les adresses privées / loopback / link-local (comme la référence)
  Host = LCase(Trim(Host))
  If Host = "localhost" Or Host = "127.0.0.1" Or Host = "::1"
    ProcedureReturn #True
  EndIf
  ; Plages IPv4 privées courantes
  Protected Part1.i
  If FindString(Host, ".") > 0
    Part1 = Val(StringField(Host, 1, "."))
    If Part1 = 10 : ProcedureReturn #True : EndIf
    If Part1 = 172
      Protected Part2.i = Val(StringField(Host, 2, "."))
      If Part2 >= 16 And Part2 <= 31 : ProcedureReturn #True : EndIf
    EndIf
    If Part1 = 192
      Protected P2.i = Val(StringField(Host, 2, "."))
      If P2 = 168 : ProcedureReturn #True : EndIf
    EndIf
    If Part1 = 169
      Protected P2b.i = Val(StringField(Host, 2, "."))
      If P2b = 254 : ProcedureReturn #True : EndIf   ; link-local / metadata
    EndIf
  EndIf
  ProcedureReturn #False
EndProcedure

Procedure.s ValidateFetchUrl(Url.s)
  Url = Trim(Url)
  If Url = "" : ProcedureReturn "" : EndIf
  Protected Scheme.s = LCase(GetURLPart(Url, #PB_URL_Protocol))
  If Scheme <> "http" And Scheme <> "https"
    ProcedureReturn ""
  EndIf
  Protected Host.s = GetURLPart(Url, #PB_URL_Site)
  If Host = "" Or IsPrivateHost(Host)
    ProcedureReturn ""
  EndIf
  ProcedureReturn Url
EndProcedure

; ---------------------------------------------------------------------------
; Récupération HTTP en mémoire
; ---------------------------------------------------------------------------
Procedure.s HttpGetMemory(Url.s, *OutStatus.Integer)
  Protected Req.i = HTTPRequestMemory(#PB_HTTP_Get, Url)
  If Not Req
    *OutStatus\i = -1
    ProcedureReturn ""
  EndIf

  Protected Status.i = Val(HTTPInfo(Req, #PB_HTTP_StatusCode))
  *OutStatus\i = Status

  Protected Result.s = ""
  If Status >= 200 And Status < 300
    Protected *Buf = HTTPMemory(Req)
    If *Buf
      Protected Size.i = MemorySize(*Buf)
      If Size > 0
        Result = PeekS(*Buf, Size, #PB_UTF8 | #PB_ByteLength)
      EndIf
    EndIf
  EndIf

  FinishHTTP(Req)
  ProcedureReturn Result
EndProcedure

; ---------------------------------------------------------------------------
; Conversion HTML -> Markdown (basique mais fonctionnelle)
; ---------------------------------------------------------------------------
Procedure.s HtmlToMarkdown(Html.s)
  Protected Md.s = Html

  ; Supprimer les blocs non désirés
  Md = ReplaceString(Md, Chr(13), " ")
  Md = ReplaceString(Md, Chr(10), " ")

  ; Supprimer script / style / head (approche par expressions simples)
  Protected i.i
  ; <script>...</script>
  Repeat
    i = FindString(LCase(Md), "<script")
    If i = 0 : Break : EndIf
    Protected EndScript.i = FindString(LCase(Md), "</script>", i)
    If EndScript = 0 : Break : EndIf
    Md = Left(Md, i - 1) + Mid(Md, EndScript + 9)
  ForEver
  ; <style>...</style>
  Repeat
    i = FindString(LCase(Md), "<style")
    If i = 0 : Break : EndIf
    Protected EndStyle.i = FindString(LCase(Md), "</style>", i)
    If EndStyle = 0 : Break : EndIf
    Md = Left(Md, i - 1) + Mid(Md, EndStyle + 8)
  ForEver

  ; Titres
  Protected h.i
  For h = 1 To 6
    Protected OpenTag.s = "<h" + Str(h) + ">"
    Protected OpenTagAttr.s = "<h" + Str(h) + " "
    Protected CloseTag.s = "</h" + Str(h) + ">"
    Protected Prefix.s = StringField(" # ## ### #### ##### ######", h + 1, " ") + " "
    ; Version sans attribut
    Repeat
      i = FindString(LCase(Md), OpenTag)
      If i = 0 : Break : EndIf
      Protected EndH.i = FindString(LCase(Md), CloseTag, i)
      If EndH = 0 : Break : EndIf
      Protected Inner.s = Mid(Md, i + Len(OpenTag), EndH - (i + Len(OpenTag)))
      Md = Left(Md, i - 1) + Prefix + Inner + Mid(Md, EndH + Len(CloseTag))
    ForEver
  Next

  ; Gras / italique (ordre important)
  Md = ReplaceString(Md, "<strong>", "**")
  Md = ReplaceString(Md, "</strong>", "**")
  Md = ReplaceString(Md, "<b>", "**")
  Md = ReplaceString(Md, "</b>", "**")
  Md = ReplaceString(Md, "<em>", "*")
  Md = ReplaceString(Md, "</em>", "*")
  Md = ReplaceString(Md, "<i>", "*")
  Md = ReplaceString(Md, "</i>", "*")

  ; Liens
  Repeat
    i = FindString(LCase(Md), "<a ")
    If i = 0 : Break : EndIf
    Protected EndA.i = FindString(LCase(Md), "</a>", i)
    If EndA = 0 : Break : EndIf
    Protected ATag.s = Mid(Md, i, EndA - i)
    Protected Href.s = ""
    Protected HrefPos.i = FindString(LCase(ATag), "href=")
    If HrefPos > 0
      Protected HrefStart.i = HrefPos + 5
      Protected Quote.s = Mid(ATag, HrefStart, 1)
      If Quote = Chr(34) Or Quote = "'"
        HrefStart + 1
        Protected HrefEnd.i = FindString(ATag, Quote, HrefStart)
        If HrefEnd > 0
          Href = Mid(ATag, HrefStart, HrefEnd - HrefStart)
        EndIf
      EndIf
    EndIf
    Protected LinkText.s = Mid(Md, i + Len(ATag), EndA - (i + Len(ATag)))
    Protected Replacement.s = "[" + Trim(LinkText) + "](" + Href + ")"
    Md = Left(Md, i - 1) + Replacement + Mid(Md, EndA + 4)
  ForEver

  ; Sauts de ligne
  Md = ReplaceString(Md, "<br>", #LF$)
  Md = ReplaceString(Md, "<br/>", #LF$)
  Md = ReplaceString(Md, "<br />", #LF$)
  Md = ReplaceString(Md, "<p>", #LF$ + #LF$)
  Md = ReplaceString(Md, "</p>", #LF$ + #LF$)

  ; Supprimer toutes les autres balises restantes
  Repeat
    i = FindString(Md, "<")
    If i = 0 : Break : EndIf
    Protected j.i = FindString(Md, ">", i)
    If j = 0 : Break : EndIf
    Md = Left(Md, i - 1) + Mid(Md, j + 1)
  ForEver

  ; Nettoyage des entités HTML basiques
  Md = ReplaceString(Md, "&nbsp;", " ")
  Md = ReplaceString(Md, "&amp;", "&")
  Md = ReplaceString(Md, "&lt;", "<")
  Md = ReplaceString(Md, "&gt;", ">")
  Md = ReplaceString(Md, "&quot;", Chr(34))

  ; Normaliser les espaces multiples
  While FindString(Md, "  ")
    Md = ReplaceString(Md, "  ", " ")
  Wend

  ProcedureReturn Trim(Md)
EndProcedure

; ---------------------------------------------------------------------------
; Outil fetch
; ---------------------------------------------------------------------------
Declare.s GetArgString(ArgsObj.i, Key.s)
Declare.i GetArgInt(ArgsObj.i, Key.s, DefaultVal.i)
Declare.i GetArgBool(ArgsObj.i, Key.s, DefaultVal.i)

Procedure.s ToolFetch(ArgsObj.i)
  Protected Url.s         = GetArgString(ArgsObj, "url")
  Protected MaxLength.i   = GetArgInt(ArgsObj, "max_length", 5000)
  Protected StartIndex.i  = GetArgInt(ArgsObj, "start_index", 0)
  Protected Raw.i         = GetArgBool(ArgsObj, "raw", 0)

  Protected SafeUrl.s = ValidateFetchUrl(Url)
  If SafeUrl = ""
    ProcedureReturn "ERREUR: URL invalide ou hote prive/loopback refuse."
  EndIf

  Protected Status.Integer
  Protected Html.s = HttpGetMemory(SafeUrl, @Status)
  If Status < 200 Or Status >= 300
    ProcedureReturn "ERREUR: echec HTTP (statut " + Str(Status) + ") pour " + SafeUrl
  EndIf
  If Html = ""
    ProcedureReturn "ERREUR: contenu vide ou illisible."
  EndIf

  Protected Content.s
  If Raw
    Content = Html
  Else
    Content = HtmlToMarkdown(Html)
  EndIf

  Protected TotalLen.i = Len(Content)
  If StartIndex >= TotalLen
    ProcedureReturn "ERREUR: start_index (" + Str(StartIndex) + ") depasse la taille du contenu (" + Str(TotalLen) + " caracteres)."
  EndIf

  Protected EndIndex.i = StartIndex + MaxLength
  If EndIndex > TotalLen : EndIndex = TotalLen : EndIf
  Protected Chunk.s = Mid(Content, StartIndex + 1, EndIndex - StartIndex)

  Protected Result.s = Chunk + #LF$ + "[Contenu: " + Str(TotalLen) + " caracteres au total"
  If EndIndex < TotalLen
    Result + " ; tronque a " + Str(EndIndex) + " ; utilisez start_index=" + Str(EndIndex) + " pour la suite"
  EndIf
  Result + "]"

  ProcedureReturn Result
EndProcedure

; ---------------------------------------------------------------------------
; Helpers JSON (identiques aux autres serveurs)
; ---------------------------------------------------------------------------
Procedure.s GetArgString(ArgsObj.i, Key.s)
  If ArgsObj And JSONType(ArgsObj) = #PB_JSON_Object
    Protected Member.i = GetJSONMember(ArgsObj, Key)
    If Member And JSONType(Member) = #PB_JSON_String
      ProcedureReturn GetJSONString(Member)
    EndIf
  EndIf
  ProcedureReturn ""
EndProcedure

Procedure.i GetArgInt(ArgsObj.i, Key.s, DefaultVal.i)
  If ArgsObj And JSONType(ArgsObj) = #PB_JSON_Object
    Protected Member.i = GetJSONMember(ArgsObj, Key)
    If Member And JSONType(Member) = #PB_JSON_Number
      ProcedureReturn GetJSONInteger(Member)
    EndIf
  EndIf
  ProcedureReturn DefaultVal
EndProcedure

Procedure.i GetArgBool(ArgsObj.i, Key.s, DefaultVal.i)
  Protected Member.i, T.i
  If ArgsObj And JSONType(ArgsObj) = #PB_JSON_Object
    Member = GetJSONMember(ArgsObj, Key)
    If Member
      T = JSONType(Member)
      If T = #PB_JSON_Boolean
        ProcedureReturn GetJSONBoolean(Member)
      ElseIf T = #PB_JSON_Number
        ProcedureReturn Bool(GetJSONInteger(Member) <> 0)
      EndIf
    EndIf
  EndIf
  ProcedureReturn DefaultVal
EndProcedure

; ---------------------------------------------------------------------------
; Catalogue MCP
; ---------------------------------------------------------------------------
Procedure AddPropString(Obj.i, Key.s, Descr.s)
  Protected P.i = AddJSONMember(Obj, Key)
  SetJSONObject(P)
  SetJSONString(AddJSONMember(P, "type"), "string")
  SetJSONString(AddJSONMember(P, "description"), Descr)
EndProcedure

Procedure AddPropInteger(Obj.i, Key.s, Descr.s, DefVal.i)
  Protected P.i = AddJSONMember(Obj, Key)
  SetJSONObject(P)
  SetJSONString(AddJSONMember(P, "type"), "integer")
  SetJSONString(AddJSONMember(P, "description"), Descr)
  SetJSONInteger(AddJSONMember(P, "default"), DefVal)
EndProcedure

Procedure AddPropBoolean(Obj.i, Key.s, Descr.s, DefVal.i)
  Protected P.i = AddJSONMember(Obj, Key)
  SetJSONObject(P)
  SetJSONString(AddJSONMember(P, "type"), "boolean")
  SetJSONString(AddJSONMember(P, "description"), Descr)
  SetJSONBoolean(AddJSONMember(P, "default"), DefVal)
EndProcedure

Procedure.i BuildToolsCatalog()
  Protected RootJSON.i = CreateJSON(#PB_Any)
  Protected RootVal.i = SetJSONObject(JSONValue(RootJSON))
  Protected ToolsArr.i = AddJSONMember(RootVal, "tools")
  SetJSONArray(ToolsArr)

  Protected ToolObj.i = AddJSONElement(ToolsArr)
  SetJSONObject(ToolObj)
  SetJSONString(AddJSONMember(ToolObj, "name"), "fetch")
  SetJSONString(AddJSONMember(ToolObj, "description"), "Recupere une URL et retourne son contenu en Markdown (ou HTML brut si raw=true).")

  Protected SchemaObj.i = AddJSONMember(ToolObj, "inputSchema")
  SetJSONObject(SchemaObj)
  SetJSONString(AddJSONMember(SchemaObj, "type"), "object")

  Protected PropsObj.i = AddJSONMember(SchemaObj, "properties")
  SetJSONObject(PropsObj)

  AddPropString(PropsObj, "url", "URL a recuperer (http/https).")
  AddPropInteger(PropsObj, "max_length", "Nombre maximum de caracteres a retourner.", 5000)
  AddPropInteger(PropsObj, "start_index", "Index de depart dans le contenu.", 0)
  AddPropBoolean(PropsObj, "raw", "Retourner le HTML brut sans conversion Markdown.", 0)

  Protected ReqArr.i = AddJSONMember(SchemaObj, "required")
  SetJSONArray(ReqArr)
  SetJSONString(AddJSONElement(ReqArr), "url")

  ProcedureReturn RootJSON
EndProcedure

; ---------------------------------------------------------------------------
; Réponses JSON-RPC
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
; Traitement d'une requete JSON-RPC
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

  If Method = "notifications/initialized"
    FreeJSON(ReqJSON)
    ProcedureReturn
  EndIf

  ; tools/list
  If Method = "tools/list"
    Protected CatalogJSON.i = BuildToolsCatalog()
    Protected IdValStr.s = "null"
    If IdMember
      If JSONType(IdMember) = #PB_JSON_String
        IdValStr = Chr(34) + GetJSONString(IdMember) + Chr(34)
      ElseIf JSONType(IdMember) = #PB_JSON_Number
        IdValStr = Str(GetJSONInteger(IdMember))
      EndIf
    EndIf
    Protected Body.s = ComposeJSON(CatalogJSON)
    SendRawLine(Chr(123) + Chr(34) + "jsonrpc" + Chr(34) + ":" + Chr(34) + "2.0" + Chr(34) + "," + Chr(34) + "id" + Chr(34) + ":" + IdValStr + "," + Chr(34) + "result" + Chr(34) + ":" + Body + Chr(125))
    FreeJSON(CatalogJSON)
    FreeJSON(ReqJSON)
    ProcedureReturn
  EndIf

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
      SetJSONString(AddJSONMember(ResultObj, "protocolVersion"), "2024-11-05")
      Protected Caps.i = AddJSONMember(ResultObj, "capabilities")
      SetJSONObject(Caps)
      SetJSONObject(AddJSONMember(Caps, "tools"))
      Protected ServerInfo.i = AddJSONMember(ResultObj, "serverInfo")
      SetJSONObject(ServerInfo)
      SetJSONString(AddJSONMember(ServerInfo, "name"), "FetchMCPServer-PureBasic")
      SetJSONString(AddJSONMember(ServerInfo, "version"), "1.0.0")

    Case "tools/call"
      Protected ParamsMember.i = GetJSONMember(RootVal, "params")
      Protected ToolName.s = ""
      Protected ArgsMember.i = #Null
      If ParamsMember And JSONType(ParamsMember) = #PB_JSON_Object
        ToolName = GetArgString(ParamsMember, "name")
        ArgsMember = GetJSONMember(ParamsMember, "arguments")
      EndIf

      Protected OutputStr.s = ""
      Protected IsErr.i = #False

      Select ToolName
        Case "fetch"
          OutputStr = ToolFetch(ArgsMember)
          If Left(OutputStr, 7) = "ERREUR:"
            IsErr = #True
          EndIf
        Default
          OutputStr = "Outil inconnu : " + ToolName
          IsErr = #True
      EndSelect

      AttachResultPayload(ResultObj, OutputStr, IsErr)

    Default
  EndSelect

  SendResponse(RespJSON)
  FreeJSON(ReqJSON)
EndProcedure

; ---------------------------------------------------------------------------
; Boucle principale
; ---------------------------------------------------------------------------
CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  If hKernel32 = 0 Or Std_GetHandle = 0 Or Std_ReadFile = 0 Or Std_WriteFile = 0
    End 1
  EndIf
CompilerEndIf

Define Line.s
While #True
  Line = ReadStdinLine()
  If Line = "" And G_EOF
    Break
  EndIf
  Line = Trim(Line)
  If Line <> ""
    ProcessRequest(Line)
  EndIf
Wend

End