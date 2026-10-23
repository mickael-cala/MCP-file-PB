; PureBasic
; ============================================================================
;  SERVEUR MCP - PureBasic (Console / Stdio) - 100 % Natif (Sans DLL / API)
; ============================================================================
;  Compilation : Options du compilateur -> Format d'exécutable: Console
;  Transport   : JSON-RPC 2.0 sur stdin / stdout (délimité par \n)
; ============================================================================

EnableExplicit

; ---------------------------------------------------------------------------
; Couche E/S stdio multi-plateforme (Windows / Linux / macOS)
;   - Lecture stdin : fiable en mode pipe, gere proprement l'EOF sur les
;     3 OS ; Input() est banni car non fiable.
;   - Ecriture stdout :
;       * Windows -> WriteFile(GetStdHandle(STD_OUTPUT_HANDLE))
;                    + FlushFileBuffers (mode pipe/stdio MCP)
;       * Linux/macOS -> write_() sur le descripteur 1 + fflush_(0)
; ---------------------------------------------------------------------------

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #C_STD_INPUT_HANDLE  = -10
  #C_STD_OUTPUT_HANDLE = -11

  ; Chargement dynamique de kernel32 : les noms ReadFile/WriteFile entrent
  ; en conflit avec des commandes PureBasic, on passe par PrototypeC.
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


Global G_AllowedRoot.s
Global G_RootSecret.s

; ---------------------------------------------------------------------------
; Utilitaires de chemins (100 % natifs)
; ---------------------------------------------------------------------------

Procedure.s GetPathSeparator()
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    ProcedureReturn "\"
  CompilerElse
    ProcedureReturn "/"
  CompilerEndIf
EndProcedure

Procedure.s EnsureTrailingSlash(Path.s)
  Protected Sep.s = GetPathSeparator()
  If Right(Path, 1) <> "/" And Right(Path, 1) <> "\"
    ProcedureReturn Path + Sep
  EndIf
  ProcedureReturn Path
EndProcedure

Procedure.s NormalizePath(Path.s)
  Protected Sep.s = GetPathSeparator()
  Path = ReplaceString(ReplaceString(Path, "/", Sep), "\", Sep)

  Protected Prefix.s = ""
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    If Mid(Path, 2, 1) = ":"
      Prefix = Left(Path, 2)
      Path = Mid(Path, 3)
    EndIf
  CompilerElse
    If Left(Path, 1) = "/"
      Prefix = "/"
      Path = Mid(Path, 2)
    EndIf
  CompilerEndIf

  NewList Segments.s()
  Protected i.i, Count.i = CountString(Path, Sep) + 1
  Protected Part.s

  For i = 1 To Count
    Part = Trim(StringField(Path, i, Sep))
    If Part = "" Or Part = "."
      ; Ignorer les séparateurs redondants et les segments neutres
    ElseIf Part = ".."
      ; Remonter d'un cran si possible
      If ListSize(Segments()) > 0
        LastElement(Segments())
        DeleteElement(Segments())
      EndIf
    Else
      AddElement(Segments())
      Segments() = Part
    EndIf
  Next

  Protected Result.s = Prefix
  ForEach Segments()
    If Result = "" Or Result = "/"
      Result + Segments()
    ElseIf Right(Result, 1) = ":"
      Result + Sep + Segments()
    Else
      Result + Sep + Segments()
    EndIf
  Next

  If Result = "" And Prefix <> ""
    Result = Prefix
  EndIf

  ProcedureReturn Result
EndProcedure

Procedure.i NativeCreateDirectories(Path.s)
  Protected Sep.s = GetPathSeparator()
  Path = ReplaceString(ReplaceString(Path, "/", Sep), "\", Sep)

  Protected i.i, Count.i = CountString(Path, Sep) + 1
  Protected SubPath.s = "", Part.s

  For i = 1 To Count
    Part = StringField(Path, i, Sep)
    If Part <> ""
      If SubPath = ""
        CompilerIf #PB_Compiler_OS = #PB_OS_Windows
          SubPath = Part
        CompilerElse
          SubPath = "/" + Part
        CompilerEndIf
      Else
        SubPath + Sep + Part
      EndIf

      If FileSize(SubPath) = -1
        CreateDirectory(SubPath)
      EndIf
    EndIf
  Next

  ProcedureReturn Bool(FileSize(Path) = -2)
EndProcedure

Procedure.s ValiderChemin(CheminDemande.s)
  CheminDemande = Trim(CheminDemande)
  If CheminDemande = ""
    ProcedureReturn ""
  EndIf

  Protected IsAbsolute.i = #False
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    If Mid(CheminDemande, 2, 1) = ":" Or Left(CheminDemande, 1) = "\" Or Left(CheminDemande, 1) = "/"
      IsAbsolute = #True
    EndIf
  CompilerElse
    If Left(CheminDemande, 1) = "/"
      IsAbsolute = #True
    EndIf
  CompilerEndIf

  Protected FullPath.s
  If Not IsAbsolute
    FullPath = NormalizePath(EnsureTrailingSlash(G_AllowedRoot) + CheminDemande)
  Else
    FullPath = NormalizePath(CheminDemande)
  EndIf

  Protected FullRoot.s = EnsureTrailingSlash(NormalizePath(G_AllowedRoot))
  Protected NormPath.s, NormRoot.s

  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    NormPath = UCase(EnsureTrailingSlash(FullPath))
    NormRoot = UCase(FullRoot)
  CompilerElse
    NormPath = EnsureTrailingSlash(FullPath)
    NormRoot = FullRoot
  CompilerEndIf

  ; Confinement sous la racine autorisée
  If Left(NormPath, Len(NormRoot)) <> NormRoot
    ProcedureReturn ""
  EndIf

  ProcedureReturn FullPath
EndProcedure

Procedure.i IsBinaryFile(Filename.s)
  Protected Ext.s = LCase(GetExtensionPart(Filename))
  Select Ext
    Case "exe", "dll", "so", "dylib", "o", "ppu", "obj", "bin", "a", "lib"
      ProcedureReturn #True
  EndSelect
  ProcedureReturn #False
EndProcedure

; ---------------------------------------------------------------------------
; Outils de manipulation de fichiers (Tools)
; ---------------------------------------------------------------------------

Procedure.s ToolListFiles(Path.s)
  Protected SafePath.s = ValiderChemin(Path)
  If SafePath = "" : ProcedureReturn "ACCES_REFUSE" : EndIf
  If FileSize(SafePath) <> -2 : ProcedureReturn "Le repertoire n'existe pas : " + Path : EndIf

  Protected Res.s = "", Count.i = 0
  Protected Dir.i = ExamineDirectory(#PB_Any, SafePath, "*")
  If Dir
    While NextDirectoryEntry(Dir)
      Protected EntryName.s = DirectoryEntryName(Dir)
      If EntryName <> "." And EntryName <> ".."
        Count + 1
        If DirectoryEntryType(Dir) = #PB_DirectoryEntry_Directory
          Res + "[DIR]  " + EntryName + #LF$
        Else
          Res + "[FILE] " + EntryName + "  (" + Str(DirectoryEntrySize(Dir)) + " octets)" + #LF$
        EndIf
      EndIf
    Wend
    FinishDirectory(Dir)
  EndIf
  ProcedureReturn SafePath + " (" + Str(Count) + " elements) :" + #LF$ + Res
EndProcedure

Procedure.s ToolReadFile(Path.s)
  Protected SafePath.s = ValiderChemin(Path)
  If SafePath = "" : ProcedureReturn "ACCES_REFUSE" : EndIf
  If FileSize(SafePath) < 0 : ProcedureReturn "Fichier introuvable : " + Path : EndIf

  Protected FileNum.i = ReadFile(#PB_Any, SafePath)
  If Not FileNum : ProcedureReturn "Impossible d'ouvrir le fichier : " + Path : EndIf

  Protected Size.q = Lof(FileNum)
  Protected BytesToRead.q = Size
  Protected Truncated.i = #False

  If BytesToRead > 20000
    BytesToRead = 20000
    Truncated = #True
  EndIf

  Protected *Buffer = AllocateMemory(BytesToRead + 1)
  Protected Content.s = ""
  If *Buffer
    ReadData(FileNum, *Buffer, BytesToRead)
    Content = PeekS(*Buffer, BytesToRead, #PB_UTF8 | #PB_ByteLength)
    FreeMemory(*Buffer)
  EndIf
  CloseFile(FileNum)

  If Truncated
    Content + #LF$ + "[... Tronque au-dela de 20000 octets ...]"
  EndIf
  ProcedureReturn Content
EndProcedure

Procedure.s ToolReadFileLines(Path.s, StartLine.i, MaxLines.i)
  Protected SafePath.s = ValiderChemin(Path)
  If SafePath = "" : ProcedureReturn "ACCES_REFUSE" : EndIf
  If FileSize(SafePath) < 0 : ProcedureReturn "Fichier introuvable : " + Path : EndIf
  If FileSize(SafePath) > 5 * 1024 * 1024 : ProcedureReturn "Fichier depasse la limite de 5 Mo." : EndIf

  Protected FileNum.i = ReadFile(#PB_Any, SafePath)
  If Not FileNum : ProcedureReturn "Impossible d'ouvrir le fichier : " + Path : EndIf

  If StartLine < 1 : StartLine = 1 : EndIf
  If MaxLines < 1 : MaxLines = 50 : EndIf
  Protected EndLine.i = StartLine + MaxLines - 1

  Protected CurrentLine.i = 1
  Protected Res.s = "", LineText.s = ""

  While Not Eof(FileNum)
    LineText = ReadString(FileNum, #PB_UTF8)
    If CurrentLine >= StartLine And CurrentLine <= EndLine
      Res + RSet(Str(CurrentLine), 5, " ") + ": " + LineText + #LF$
    EndIf
    If CurrentLine > EndLine : Break : EndIf
    CurrentLine + 1
  Wend

  CloseFile(FileNum)
  ProcedureReturn Res
EndProcedure

Procedure.s ToolWriteFile(Path.s, Content.s)
  Protected SafePath.s = ValiderChemin(Path)
  If SafePath = "" : ProcedureReturn "ACCES_REFUSE" : EndIf

  Protected FileNum.i = CreateFile(#PB_Any, SafePath)
  If Not FileNum : ProcedureReturn "Erreur lors de la creation du fichier : " + Path : EndIf

  WriteString(FileNum, Content, #PB_UTF8)
  CloseFile(FileNum)
  ProcedureReturn "Fichier ecrit avec succes (" + Str(StringByteLength(Content, #PB_UTF8)) + " octets) : " + SafePath
EndProcedure

Procedure.s ToolCreateDirectory(Path.s)
  Protected SafePath.s = ValiderChemin(Path)
  If SafePath = "" : ProcedureReturn "ACCES_REFUSE" : EndIf
  If FileSize(SafePath) = -2 : ProcedureReturn "Le repertoire existe deja : " + SafePath : EndIf

  If NativeCreateDirectories(SafePath)
    ProcedureReturn "Repertoire cree : " + SafePath
  Else
    ProcedureReturn "Impossible de creer le repertoire : " + SafePath
  EndIf
EndProcedure

Procedure.s ToolDeleteFile(Path.s)
  Protected SafePath.s = ValiderChemin(Path)
  If SafePath = "" : ProcedureReturn "ACCES_REFUSE" : EndIf

  If FileSize(SafePath) = -2
    If DeleteDirectory(SafePath, "", #PB_FileSystem_Recursive)
      ProcedureReturn "Dossier supprime : " + SafePath
    Else
      ProcedureReturn "Impossible de supprimer le dossier : " + SafePath
    EndIf
  ElseIf FileSize(SafePath) >= 0
    If DeleteFile(SafePath)
      ProcedureReturn "Fichier supprime : " + SafePath
    Else
      ProcedureReturn "Impossible de supprimer le fichier : " + SafePath
    EndIf
  EndIf
  ProcedureReturn "Cible introuvable : " + SafePath
EndProcedure

Procedure.s ToolMoveFile(OldPath.s, NewPath.s)
  Protected SafeOld.s = ValiderChemin(OldPath)
  Protected SafeNew.s = ValiderChemin(NewPath)
  If SafeOld = "" Or SafeNew = "" : ProcedureReturn "ACCES_REFUSE" : EndIf
  If FileSize(SafeOld) = -1 : ProcedureReturn "Source introuvable : " + SafeOld : EndIf

  If RenameFile(SafeOld, SafeNew)
    ProcedureReturn "Deplace avec succes : " + SafeOld + " -> " + SafeNew
  Else
    If CopyFile(SafeOld, SafeNew)
      DeleteFile(SafeOld)
      ProcedureReturn "Fichier deplace (copie/suppression) : " + SafeOld + " -> " + SafeNew
    EndIf
  EndIf
  ProcedureReturn "Echec du deplacement de " + SafeOld + " vers " + SafeNew
EndProcedure

Procedure.s ToolGetFileInfo(Path.s)
  Protected SafePath.s = ValiderChemin(Path)
  If SafePath = "" : ProcedureReturn "ACCES_REFUSE" : EndIf
  If FileSize(SafePath) = -1 : ProcedureReturn "Fichier ou dossier introuvable : " + SafePath : EndIf

  Protected IsDir.s = "non"
  Protected Size.q = FileSize(SafePath)
  If Size = -2
    IsDir = "oui"
    Size = 0
  EndIf

  Protected Stamp.i = GetFileDate(SafePath, #PB_Date_Modified)
  Protected DateText.s = FormatDate("%YYYY-%MM-%DD %HH:%II:%SS", Stamp)

  Protected Res.s = "Chemin : " + SafePath + #LF$
  Res + "Taille : " + Str(Size) + " octets" + #LF$
  Res + "Horodatage : " + DateText + #LF$
  Res + "Est un dossier : " + IsDir
  ProcedureReturn Res
EndProcedure

Procedure SearchRecursive(BaseDir.s, Pattern.s, List Matches.s(), *Count.Integer)
  If *Count\i >= 100 : ProcedureReturn : EndIf

  Protected Dir.i = ExamineDirectory(#PB_Any, BaseDir, "*")
  If Dir
    While NextDirectoryEntry(Dir)
      Protected Name.s = DirectoryEntryName(Dir)
      If Name <> "." And Name <> ".."
        Protected Full.s = EnsureTrailingSlash(BaseDir) + Name
        If DirectoryEntryType(Dir) = #PB_DirectoryEntry_Directory
          SearchRecursive(Full, Pattern, Matches(), *Count)
        Else
          If Not IsBinaryFile(Full) And DirectoryEntrySize(Dir) <= 2 * 1024 * 1024
            Protected F.i = ReadFile(#PB_Any, Full)
            If F
              Protected LineNum.i = 0
              While Not Eof(F)
                LineNum + 1
                Protected Line.s = ReadString(F, #PB_UTF8)
                If FindString(LCase(Line), LCase(Pattern))
                  AddElement(Matches())
                  Matches() = Full + ":" + Str(LineNum) + ": " + Trim(Line)
                  *Count\i + 1
                  If *Count\i >= 100 : Break : EndIf
                EndIf
              Wend
              CloseFile(F)
            EndIf
          EndIf
        EndIf
      EndIf
      If *Count\i >= 100 : Break : EndIf
    Wend
    FinishDirectory(Dir)
  EndIf
EndProcedure

Procedure.s ToolSearchFiles(Path.s, Pattern.s)
  Protected SafePath.s = ValiderChemin(Path)
  If SafePath = "" : ProcedureReturn "ACCES_REFUSE" : EndIf
  If FileSize(SafePath) <> -2 : ProcedureReturn "Repertoire introuvable : " + SafePath : EndIf

  NewList Matches.s()
  Protected Total.Integer\i = 0
  SearchRecursive(SafePath, Pattern, Matches(), @Total)

  Protected Res.s = Str(Total\i) + " resultat(s) pour " + #DQUOTE$ + Pattern + #DQUOTE$ + " :" + #LF$
  ForEach Matches()
    Res + Matches() + #LF$
  Next
  ProcedureReturn Res
EndProcedure

Procedure.s ToolChangeRoot(NewRoot.s, Secret.s)
  If G_RootSecret = ""
    ProcedureReturn "Modification refusee : MCP_ROOT_SECRET non configure cote serveur."
  EndIf
  If Secret <> G_RootSecret
    ProcedureReturn "Modification refusee : secret invalide."
  EndIf
  If FileSize(NewRoot) <> -2
    ProcedureReturn "Repertoire introuvable : " + NewRoot
  EndIf

  G_AllowedRoot = NormalizePath(NewRoot)
  ProcedureReturn "Racine autorisee modifiee : " + G_AllowedRoot
EndProcedure

; ---------------------------------------------------------------------------
; Construction JSON-RPC & Catalogue MCP
; ---------------------------------------------------------------------------


Procedure AddProp(Obj.i, Key.s, Type.s, Descr.s)
  Protected P.i = AddJSONMember(Obj, Key)
  SetJSONObject(P)
  SetJSONString(AddJSONMember(P, "type"), Type)
  SetJSONString(AddJSONMember(P, "description"), Descr)
EndProcedure

Procedure AddReq(Arr.i, Key.s)
  SetJSONString(AddJSONElement(Arr), Key)
EndProcedure

Procedure ToolDef(ToolsArr.i, Name.s, Descr.s, PropsSpec.s, ReqSpec.s)
  ; Construit la definition d'un outil MCP. PropsSpec = proprietes separes par
  ; des ';', chaque entree etant 'cle|type|description'. ReqSpec = cles
  ; requises separees par des ';'. Tout est cree nativement dans le document
  ; cible (pas de valeurs partagees -> pas de segfault).
  Protected ToolObj.i = AddJSONElement(ToolsArr)
  SetJSONObject(ToolObj)
  SetJSONString(AddJSONMember(ToolObj, "name"), Name)
  SetJSONString(AddJSONMember(ToolObj, "description"), Descr)
  Protected SchemaObj.i = AddJSONMember(ToolObj, "inputSchema")
  SetJSONObject(SchemaObj)
  SetJSONString(AddJSONMember(SchemaObj, "type"), "object")
  Protected PropsObj.i = AddJSONMember(SchemaObj, "properties")
  SetJSONObject(PropsObj)
  Protected ReqArr.i = AddJSONMember(SchemaObj, "required")
  SetJSONArray(ReqArr)

  Protected i.i, n.i = CountString(PropsSpec, ";") + 1, Entry.s, K.s, T.s, D.s
  For i = 1 To n
    Entry = Trim(StringField(PropsSpec, i, ";"))
    If Entry <> ""
      K = Trim(StringField(Entry, 1, "|"))
      T = Trim(StringField(Entry, 2, "|"))
      D = Trim(StringField(Entry, 3, "|"))
      AddProp(PropsObj, K, T, D)
    EndIf
  Next
  n = CountString(ReqSpec, ";") + 1
  For i = 1 To n
    Entry = Trim(StringField(ReqSpec, i, ";"))
    If Entry <> "" : AddReq(ReqArr, Entry) : EndIf
  Next
EndProcedure

Procedure.i BuildToolsCatalog()
  Protected RootJSON.i = CreateJSON(#PB_Any)
  Protected RootVal.i = SetJSONObject(JSONValue(RootJSON))
  Protected ToolsArr.i = AddJSONMember(RootVal, "tools")
  SetJSONArray(ToolsArr)

  ToolDef(ToolsArr, "list_files", "Lister le contenu d'un repertoire (confine a la racine autorisee)", "path|string|Chemin du repertoire", "path")
  ToolDef(ToolsArr, "read_file", "Lire un fichier texte (tronque au-dela de 20000 octets)", "path|string|Chemin du fichier", "path")
  ToolDef(ToolsArr, "read_file_lines", "Lire une plage de lignes (fichier limite a 5 Mo)", "path|string|Chemin;startLine|integer|Ligne de depart (defaut:1);maxLines|integer|Nombre de lignes (defaut:50)", "path")
  ToolDef(ToolsArr, "write_file", "Ecrire/creer un fichier texte", "path|string|Chemin;content|string|Contenu", "path;content")
  ToolDef(ToolsArr, "create_directory", "Creer un repertoire", "path|string|Chemin", "path")
  ToolDef(ToolsArr, "delete_file", "Supprimer un fichier ou dossier vide", "path|string|Chemin", "path")
  ToolDef(ToolsArr, "move_file", "Deplacer ou renommer un fichier", "oldPath|string|Chemin source;newPath|string|Chemin destination", "oldPath;newPath")
  ToolDef(ToolsArr, "get_file_info", "Infos detaillees fichier/dossier", "path|string|Chemin", "path")
  ToolDef(ToolsArr, "search_files", "Rechercher du texte (recursif)", "path|string|Repertoire de depart;pattern|string|Texte recherche", "path;pattern")
  ToolDef(ToolsArr, "change_root", "CHANGER LA ZONE AUTORISEE", "newRoot|string|Nouveau repertoire racine;secret|string|Mot de passe MCP_ROOT_SECRET", "newRoot;secret")

  ProcedureReturn RootJSON
EndProcedure

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
; Traitement d'une requête JSON-RPC
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

  ; Notifications : pas de réponse attendue
  If Method = "notifications/initialized"
    FreeJSON(ReqJSON)
    ProcedureReturn
  EndIf

  ; Cas particulier tools/list : émission directe du catalogue composé
  If Method = "tools/list"
    ; Reponse conforme JSON-RPC : le catalogue est compose en un seul objet
    ; "result" puis envoye sur une ligne (protocole stdio delimite par \n).
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

  ; Création de la réponse JSON-RPC standard
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
      SetJSONString(AddJSONMember(ServerInfo, "name"), "FileMCPServer-PureBasic")
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
        Case "list_files"
          OutputStr = ToolListFiles(GetArgString(ArgsMember, "path"))
        Case "read_file"
          OutputStr = ToolReadFile(GetArgString(ArgsMember, "path"))
        Case "read_file_lines"
          OutputStr = ToolReadFileLines(GetArgString(ArgsMember, "path"), GetArgInt(ArgsMember, "startLine", 1), GetArgInt(ArgsMember, "maxLines", 50))
        Case "write_file"
          OutputStr = ToolWriteFile(GetArgString(ArgsMember, "path"), GetArgString(ArgsMember, "content"))
        Case "create_directory"
          OutputStr = ToolCreateDirectory(GetArgString(ArgsMember, "path"))
        Case "delete_file"
          OutputStr = ToolDeleteFile(GetArgString(ArgsMember, "path"))
        Case "move_file"
          OutputStr = ToolMoveFile(GetArgString(ArgsMember, "oldPath"), GetArgString(ArgsMember, "newPath"))
        Case "get_file_info"
          OutputStr = ToolGetFileInfo(GetArgString(ArgsMember, "path"))
        Case "search_files"
          OutputStr = ToolSearchFiles(GetArgString(ArgsMember, "path"), GetArgString(ArgsMember, "pattern"))
        Case "change_root"
          OutputStr = ToolChangeRoot(GetArgString(ArgsMember, "newRoot"), GetArgString(ArgsMember, "secret"))
        Default
          OutputStr = "Outil inconnu : " + ToolName
          IsErr = #True
      EndSelect

      If OutputStr = "ACCES_REFUSE"
        OutputStr = "Erreur : Acces refuse en dehors de la zone autorisee."
        IsErr = #True
      ElseIf FindString(OutputStr, "Erreur") = 1 Or FindString(OutputStr, "Impossible") = 1 Or FindString(OutputStr, "Echec") = 1 Or FindString(OutputStr, "introuvable") > 0 Or FindString(OutputStr, "refusee") > 0 Or FindString(OutputStr, "depasse") > 0
        IsErr = #True
      EndIf

      AttachResultPayload(ResultObj, OutputStr, IsErr)

    Default
      ; Autres requêtes
  EndSelect

  SendResponse(RespJSON)
  FreeJSON(ReqJSON)
EndProcedure

; ---------------------------------------------------------------------------
; Lecture stdin fiable en mode pipe (Windows : ReadFile sur le handle stdin,
; Linux/macOS : read_() sur le descripteur 0)
; ---------------------------------------------------------------------------

Global G_InBufSize.i   = 65536
Global *G_InBuf        = AllocateMemory(G_InBufSize)
Global G_InDataLen.i   = 0     ; octets valides dans le buffer
Global G_InPos.i       = 0     ; position de lecture courante
Global G_EOF.i         = #False

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
  ; Retourne "" sur EOF reel (fin de flux stdin) ; G_EOF est positionne
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

    If Found
      Break
    EndIf

    ; Pas de \n trouve : garder le reste, re-remplir
    Protected Remaining.i = G_InDataLen - G_InPos
    If Remaining > 0
      MoveMemory(*G_InBuf + G_InPos, *G_InBuf, Remaining)
    EndIf
    G_InDataLen = Remaining
    G_InPos = Remaining

    If Not FillInputBuffer()
      ; EOF sans newline final -> retourner ce qui reste
      If G_InDataLen > G_InPos
        G_InPos = G_InDataLen
      EndIf
      Break
    EndIf

    ; Guard anti-debordement : ligne trop longue -> on tronque
    If G_InDataLen >= G_InBufSize
      G_InPos = G_InDataLen
      Break
    EndIf
  Wend

  Protected Length.i = G_InPos - 1 - Start
  If Length < 0 : Length = 0 : EndIf
  If Length > 0 And PeekB(*G_InBuf + Start + Length - 1) = $0D
    Length - 1                 ; retirer un \r eventuel (CRLF)
  EndIf
  ProcedureReturn PeekS(*G_InBuf + Start, Length, #PB_UTF8 | #PB_ByteLength)
EndProcedure

; ---------------------------------------------------------------------------
; Boucle Principale
; ---------------------------------------------------------------------------

G_AllowedRoot = GetEnvironmentVariable("MCP_ROOT")
If G_AllowedRoot = ""
  G_AllowedRoot = GetCurrentDirectory()
EndIf
G_AllowedRoot = NormalizePath(G_AllowedRoot)

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  ; Verifier que la couche E/S stdio (kernel32) est bien chargee
  If hKernel32 = 0 Or Std_GetHandle = 0 Or Std_ReadFile = 0 Or Std_WriteFile = 0
    End 1
  EndIf
CompilerEndIf

G_RootSecret = GetEnvironmentVariable("MCP_ROOT_SECRET")

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

End
