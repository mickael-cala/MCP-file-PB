; ============================================================================
;  SERVEUR MCP - Sequential Thinking (PureBasic Console / Stdio)
;  Calque sur la structure de fileMCP.pb (stdio 100% natif, JSON-RPC 2.0)
; ============================================================================
;  Compilation : Options du compilateur -> Format d'exécutable: Console
;  Transport   : JSON-RPC 2.0 sur stdin / stdout (délimité par \n)
; ============================================================================

EnableExplicit

; ---------------------------------------------------------------------------
; Couche E/S stdio (identique à fileMCP.pb)
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
; Etat des sessions de raisonnement
; ---------------------------------------------------------------------------
Structure ThoughtData
  Thought.s
  ThoughtNumber.i
  TotalThoughts.i
  NextThoughtNeeded.i
  IsRevision.i
  RevisesThought.i
  BranchFromThought.i
  BranchId.s
EndStructure

Global NewList ThoughtHistory.ThoughtData()
Global NewMap Branches.i()   ; branchId -> nombre de pensées sur cette branche

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

Procedure AddPropBoolean(Obj.i, Key.s, Descr.s)
  Protected P.i = AddJSONMember(Obj, Key)
  SetJSONObject(P)
  SetJSONString(AddJSONMember(P, "type"), "boolean")
  SetJSONString(AddJSONMember(P, "description"), Descr)
EndProcedure

Procedure.i BuildToolsCatalog()
  Protected RootJSON.i = CreateJSON(#PB_Any)
  Protected RootVal.i = SetJSONObject(JSONValue(RootJSON))
  Protected ToolsArr.i = AddJSONMember(RootVal, "tools")
  SetJSONArray(ToolsArr)

  Protected ToolObj.i = AddJSONElement(ToolsArr)
  SetJSONObject(ToolObj)
  SetJSONString(AddJSONMember(ToolObj, "name"), "sequential_thinking")
  SetJSONString(AddJSONMember(ToolObj, "description"), "Enregistre une etape de raisonnement et retourne l'etat courant (numero, total, revisions, branches).")

  Protected SchemaObj.i = AddJSONMember(ToolObj, "inputSchema")
  SetJSONObject(SchemaObj)
  SetJSONString(AddJSONMember(SchemaObj, "type"), "object")

  Protected PropsObj.i = AddJSONMember(SchemaObj, "properties")
  SetJSONObject(PropsObj)

  AddPropString(PropsObj, "thought", "Le contenu de l'etape de raisonnement courante.")
  AddPropInteger(PropsObj, "thoughtNumber", "Numero de l'etape courante (commence a 1).", 1)
  AddPropInteger(PropsObj, "totalThoughts", "Nombre total d'etapes estimees.", 1)
  AddPropBoolean(PropsObj, "nextThoughtNeeded", "Indique si une autre etape est necessaire.")
  AddPropBoolean(PropsObj, "isRevision", "Indique si cette etape revise une etape precedente.")
  AddPropInteger(PropsObj, "revisesThought", "Numero de l'etape revisee (si isRevision).", 0)
  AddPropInteger(PropsObj, "branchFromThought", "Numero de l'etape d'ou diverge une branche.", 0)
  AddPropString(PropsObj, "branchId", "Identifiant de la branche de raisonnement.")

  Protected ReqArr.i = AddJSONMember(SchemaObj, "required")
  SetJSONArray(ReqArr)
  SetJSONString(AddJSONElement(ReqArr), "thought")
  SetJSONString(AddJSONElement(ReqArr), "thoughtNumber")
  SetJSONString(AddJSONElement(ReqArr), "totalThoughts")
  SetJSONString(AddJSONElement(ReqArr), "nextThoughtNeeded")

  ProcedureReturn RootJSON
EndProcedure

; ---------------------------------------------------------------------------
; Helpers d'arguments
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
; Outil principal
; ---------------------------------------------------------------------------
Procedure.s ToolSequentialThinking(ArgsObj.i)
  Protected Thought.s        = GetArgString(ArgsObj, "thought")
  Protected ThoughtNum.i     = GetArgInt(ArgsObj, "thoughtNumber", 0)
  Protected TotalThoughts.i  = GetArgInt(ArgsObj, "totalThoughts", 0)
  Protected NextNeeded.i     = GetArgBool(ArgsObj, "nextThoughtNeeded", 0)
  Protected IsRevision.i     = GetArgBool(ArgsObj, "isRevision", 0)
  Protected RevisesThought.i = GetArgInt(ArgsObj, "revisesThought", 0)
  Protected BranchFrom.i     = GetArgInt(ArgsObj, "branchFromThought", 0)
  Protected BranchId.s       = GetArgString(ArgsObj, "branchId")

  If Trim(Thought) = ""
    ProcedureReturn "ERREUR: le parametre 'thought' ne peut pas etre vide."
  EndIf
  If ThoughtNum < 1
    ProcedureReturn "ERREUR: 'thoughtNumber' doit etre un entier >= 1."
  EndIf
  If TotalThoughts < 1
    TotalThoughts = ThoughtNum
  EndIf
  If TotalThoughts < ThoughtNum
    TotalThoughts = ThoughtNum
  EndIf

  AddElement(ThoughtHistory())
  ThoughtHistory()\Thought           = Thought
  ThoughtHistory()\ThoughtNumber     = ThoughtNum
  ThoughtHistory()\TotalThoughts     = TotalThoughts
  ThoughtHistory()\NextThoughtNeeded = NextNeeded
  ThoughtHistory()\IsRevision        = IsRevision
  ThoughtHistory()\RevisesThought    = RevisesThought
  ThoughtHistory()\BranchFromThought = BranchFrom
  ThoughtHistory()\BranchId          = BranchId

  If BranchId <> ""
    If FindMapElement(Branches(), BranchId)
      Branches() = Branches() + 1
    Else
      AddMapElement(Branches(), BranchId)
      Branches() = 1
    EndIf
  EndIf

  ; Reponse structuree (meme forme que l'implementation de reference)
  Protected RespJSON.i = CreateJSON(#PB_Any)
  Protected Root.i = SetJSONObject(JSONValue(RespJSON))
  SetJSONInteger(AddJSONMember(Root, "thoughtNumber"), ThoughtNum)
  SetJSONInteger(AddJSONMember(Root, "totalThoughts"), TotalThoughts)
  SetJSONBoolean(AddJSONMember(Root, "nextThoughtNeeded"), Bool(NextNeeded))

  Protected BranchArr.i = AddJSONMember(Root, "branches")
  SetJSONArray(BranchArr)
  ForEach Branches()
    SetJSONString(AddJSONElement(BranchArr), MapKey(Branches()))
  Next

  SetJSONInteger(AddJSONMember(Root, "thoughtHistoryLength"), ListSize(ThoughtHistory()))

  Protected Out.s = ComposeJSON(RespJSON)
  FreeJSON(RespJSON)
  ProcedureReturn Out
EndProcedure

; ---------------------------------------------------------------------------
; Reponses JSON-RPC
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

  ; tools/list : emission directe du catalogue
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
      SetJSONString(AddJSONMember(ServerInfo, "name"), "SequentialThinkingMCPServer-PureBasic")
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
        Case "sequential_thinking"
          OutputStr = ToolSequentialThinking(ArgsMember)
          If Left(OutputStr, 7) = "ERREUR:"
            IsErr = #True
          EndIf
        Default
          OutputStr = "Outil inconnu : " + ToolName
          IsErr = #True
      EndSelect

      AttachResultPayload(ResultObj, OutputStr, IsErr)

    Default
      ; Methode non supportee
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