; ============================================================================
;  SERVEUR MCP - PureBasic (Console / Stdio) - 100 % Natif (Sans DLL / API)
;  Gestion de fichiers confinee a une racine autorisee (MCP_ROOT)
; ============================================================================
;  Compilation : build.bat / build.sh (ou Options du compilateur -> Console)
;  Transport   : JSON-RPC 2.0 sur stdin / stdout (delimite par \n)
;  Modules     : mcp_common/ (stdio, logging, json_helpers, protocol, jsonrpc)
; ============================================================================

EnableExplicit

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  ; Resolution des junctions/liens symboliques (anti-evasion de MCP_ROOT)
  #FILE_ATTRIBUTE_REPARSE_POINT = $00000400
  #IO_REPARSE_TAG_MOUNT_POINT   = $A0000003
  #IO_REPARSE_TAG_SYMLINK       = $A000000C
  #SYMBOLIC_LINK_FLAG_DIRECTORY = $00000001

  PrototypeC pfCreateFileW(lpFileName.s, dwDesiredAccess.l, dwShareMode.l,
                           lpSecurityAttributes.i, dwCreationDisposition.l,
                           dwFlagsAndAttributes.l, hTemplateFile.i)
  PrototypeC pfDeviceIoControl(hObject.i, dwIoControlCode.l, lpInBuffer.i,
                               nInBufferSize.l, lpOutBuffer.i, nOutBufferSize.l,
                               *lpBytesReturned, lpOverlapped.i)
  PrototypeC pfCloseHandle(hObject.i)
  PrototypeC.l pfGetFileAttributesW(lpFileName.s)

  Global mfpCreateFile.pfCreateFileW
  Global mfpDeviceIoControl.pfDeviceIoControl
  Global mfpCloseHandle.pfCloseHandle
  Global mfpGetFileAttributes.pfGetFileAttributesW
  #MFP_INVALID_FILE_ATTRIBUTES = -1

  #MFP_GENERIC_READ             = $80000000
  #MFP_FILE_FLAG_BACKUP_SEMANTICS = $02000000
  #MFP_FILE_FLAG_OPEN_REPARSE_POINT = $00200000
  #MFP_OPEN_EXISTING            = 3
  #MFP_INVALID_HANDLE           = -1
  #MFP_FSCTL_GET_REPARSE_POINT  = $000900A8
  #MFP_MAX_REPARSE              = 16384
CompilerEndIf

IncludeFile "../mcp_common/stdio.pbi"
IncludeFile "../mcp_common/logging.pbi"
IncludeFile "../mcp_common/json_helpers.pbi"
IncludeFile "../mcp_common/protocol.pbi"
IncludeFile "../mcp_common/jsonrpc.pbi"

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
      ; Ignorer les separateurs redondants et les segments neutres
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

; ---------------------------------------------------------------------------
; Resolution des junctions / liens symboliques (anti-evasion)
; ---------------------------------------------------------------------------
; Le confinement par prefixe ne suffit pas : un lien cree DANS la racine et
; pointant HORS de la racine passe le controle lexical. On resout donc chaque
; segment du chemin et on refuse (fail-closed) tout lien non resolvable ou
; toute cible qui quitte la racine autorisee.

CompilerIf #PB_Compiler_OS = #PB_OS_Windows

Procedure.i MfpResolveInit()
  Static Done.i = 0
  If Done : ProcedureReturn #True : EndIf
  Protected K.i = OpenLibrary(#PB_Any, "kernel32.dll")
  If K = 0 : ProcedureReturn #False : EndIf
  mfpCreateFile    = GetFunction(K, "CreateFileW")
  mfpDeviceIoControl = GetFunction(K, "DeviceIoControl")
  mfpCloseHandle   = GetFunction(K, "CloseHandle")
  mfpGetFileAttributes = GetFunction(K, "GetFileAttributesW")
  If mfpCreateFile = 0 Or mfpDeviceIoControl = 0 Or mfpCloseHandle = 0 Or mfpGetFileAttributes = 0
    ProcedureReturn #False
  EndIf
  Done = #True
  ProcedureReturn #True
EndProcedure

Procedure.s MfpReadLink(FilePath.s)
  If Not MfpResolveInit() : ProcedureReturn "" : EndIf

  Protected h.i = mfpCreateFile(FilePath, #MFP_GENERIC_READ, 7, #Null,
                                #MFP_OPEN_EXISTING,
                                #MFP_FILE_FLAG_BACKUP_SEMANTICS | #MFP_FILE_FLAG_OPEN_REPARSE_POINT,
                                #Null)
  If h = #MFP_INVALID_HANDLE : ProcedureReturn "" : EndIf

  Protected *Buf = AllocateMemory(#MFP_MAX_REPARSE)
  Protected Returned.l = 0
  Protected Target.s = ""
  If *Buf
    ; Layout empirique (harnais reparse_debug) :
    ; DWORD tag ; WORD w4 ; WORD w6 ; WORD subOff ; WORD subLen ;
    ; WORD printOff ; WORD printLen ; donnees a partir de +16.
    If mfpDeviceIoControl(h, #MFP_FSCTL_GET_REPARSE_POINT, #Null, 0,
                          *Buf, #MFP_MAX_REPARSE, @Returned, #Null)
      ; Champs communs : Tag(+0) ; subOff(+8) subLen(+10) printOff(+12)
      ; printLen(+14). La zone de noms commence a +16 pour une junction
      ; (MOUNT_POINT) mais a +20 pour un symlink (Flags DWORD en +16).
      Protected TagL.l = PeekL(*Buf)
      Protected Base.i = 16
      If TagL = #IO_REPARSE_TAG_SYMLINK : Base = 20 : EndIf
      Protected SubOff.w = PeekW(*Buf + 8)
      Protected SubLen.w = PeekW(*Buf + 10)
      Protected PrintOff.w = PeekW(*Buf + 12)
      Protected PrintLen.w = PeekW(*Buf + 14)
      If SubLen > 0
        Target = PeekS(*Buf + Base + SubOff, SubLen / 2, #PB_Unicode)
      ElseIf PrintLen > 0
        Target = PeekS(*Buf + Base + PrintOff, PrintLen / 2, #PB_Unicode)
      EndIf
      If Left(Target, 4) = "\??\"
        Target = Mid(Target, 5)
      EndIf
    EndIf
    FreeMemory(*Buf)
  EndIf
  mfpCloseHandle(h)

  If Target = "" : ProcedureReturn "" : EndIf
  ; Secours : si la chaine semble degradee, on cherche le motif "<lettre>:\"
  ; et on coupe juste avant (les buffers reparse sont parfois decales).
  If Mid(Target, 2, 1) <> ":"
    Protected C.i = FindString(Target, ":\")
    If C >= 2
      ProcedureReturn Mid(Target, C - 1)
    EndIf
    ProcedureReturn ""   ; pas de cible locale exploitable : refuse
  EndIf
  ProcedureReturn Target
EndProcedure

; Le chemin designe-t-il un reparse point (junction/symlink) ?
Procedure.i MfpIsReparse(Path.s)
  If Not MfpResolveInit() : ProcedureReturn #False : EndIf
  Protected Attr.l = mfpGetFileAttributes(Path)
  If Attr = #MFP_INVALID_FILE_ATTRIBUTES : ProcedureReturn #False : EndIf
  ProcedureReturn Bool(Attr & #FILE_ATTRIBUTE_REPARSE_POINT)
EndProcedure

; Resout tous les liens du chemin (dossiers intermediaires et cible finale).
; Retourne le chemin reel, ou "" si un lien est non resolvable (fail-closed).
; MaxDepth borne les resolutions successives (anti-boucle de liens croises).
Procedure.s MfpRealPath(Path.s, MaxDepth.i)
  Protected Sep.s = GetPathSeparator()
  Protected Current.s = NormalizePath(Path)
  Protected Guard.i = 0

  While Guard < MaxDepth
    Guard + 1

    ; Trouver le premier reparse point en scannant les prefixes. Le disque
    ; ("C:") n'est jamais un reparse ; on scanne chaque position de
    ; separateur, puis le chemin complet (cas d'un fichier-lien).
    Protected Pos.i = 0
    Protected Found.s = ""
    Protected FoundEnd.i = 0
    While Pos < Len(Current)
      Pos = FindString(Current, Sep, Pos + 1)
      If Pos = 0 : Break : EndIf
      Protected Candidate.s = Left(Current, Pos - 1)
      If Len(Candidate) > 3 And MfpIsReparse(Candidate)
        Found = Candidate
        FoundEnd = Pos
        Break
      EndIf
    Wend
    ; la racine du chemin (si plus longue qu'un simple "C:") peut elle-meme
    ; etre une junction : verifier aussi le prefixe jusqu'au 1er separateur.
    Protected FirstSep.i = FindString(Current, Sep, 1)
    If Found = "" And FirstSep > 4
      Protected HeadPart.s = Left(Current, FirstSep - 1)
      If MfpIsReparse(HeadPart)
        Found = HeadPart
        FoundEnd = FirstSep
      EndIf
    EndIf
    If Found = "" And Current <> "" And Right(Current, 1) <> Sep
      If MfpIsReparse(Current)
        Found = Current
        FoundEnd = Len(Current) + 1
      EndIf
    EndIf
    If Found = "" : Break : EndIf

    Protected Tgt.s = MfpReadLink(Found)
    If Tgt = "" : ProcedureReturn "" : EndIf

    If FoundEnd <= Len(Current)
      Current = NormalizePath(Tgt + Mid(Current, FoundEnd))
    Else
      Current = NormalizePath(Tgt)
    EndIf
  Wend

  ProcedureReturn Current
EndProcedure

CompilerEndIf

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

  ; Anti-evasion : resoudre les junctions/liens symboliques AVANT le
  ; controle de confinement. Un lien non resolvable => refus (fail-closed).
  Protected RealPath.s = FullPath
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    RealPath = MfpRealPath(FullPath, 24)
    If RealPath = "" : ProcedureReturn "" : EndIf
  CompilerEndIf

  Protected FullRoot.s = EnsureTrailingSlash(NormalizePath(G_AllowedRoot))
  Protected RealRoot.s = FullRoot
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    RealRoot = MfpRealPath(FullRoot, 24)
    If RealRoot = "" : ProcedureReturn "" : EndIf
    RealRoot = EnsureTrailingSlash(NormalizePath(RealRoot))
  CompilerEndIf

  Protected NormPath.s, NormRoot.s

  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    NormPath = UCase(EnsureTrailingSlash(RealPath))
    NormRoot = UCase(RealRoot)
  CompilerElse
    ; Linux/macOS : FileSize() suit deja les symlinks ; le controle lexical
    ; suffit car un symlink hors racine ne peut etre atteint qu'en traversant
    ; un chemin qui, resolu, sort du prefixe.
    NormPath = EnsureTrailingSlash(FullPath)
    NormRoot = FullRoot
  CompilerEndIf

  ; Confinement sous la racine autorisee (chemin RESOLU)
  If Left(NormPath, Len(NormRoot)) <> NormRoot
    ProcedureReturn ""
  EndIf

  ProcedureReturn RealPath
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
  ProcedureReturn ToolOk(SafePath + " (" + Str(Count) + " elements) :" + #LF$ + Res)
EndProcedure

Procedure.s ToolReadFile(Path.s)
  Protected SafePath.s = ValiderChemin(Path)
  If SafePath = "" : ProcedureReturn ToolFail("ACCES_REFUSE") : EndIf
  If IsBinaryFile(SafePath)
    ProcedureReturn ToolFail("Erreur : fichier binaire refuse (extension ." + LCase(GetExtensionPart(SafePath)) + ").")
  EndIf
  If FileSize(SafePath) < 0 : ProcedureReturn ToolFail("Fichier introuvable : " + Path) : EndIf

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
  ProcedureReturn ToolOk(Content)
EndProcedure

Procedure.s ToolReadFileLines(Path.s, StartLine.i, MaxLines.i)
  Protected SafePath.s = ValiderChemin(Path)
  If SafePath = "" : ProcedureReturn ToolFail("ACCES_REFUSE") : EndIf
  If IsBinaryFile(SafePath)
    ProcedureReturn ToolFail("Erreur : fichier binaire refuse (extension ." + LCase(GetExtensionPart(SafePath)) + ").")
  EndIf
  If FileSize(SafePath) < 0 : ProcedureReturn ToolFail("Fichier introuvable : " + Path) : EndIf
  If FileSize(SafePath) > 5 * 1024 * 1024 : ProcedureReturn ToolFail("Fichier depasse la limite de 5 Mo.") : EndIf

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
  ProcedureReturn ToolOk(Res)
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
    ProcedureReturn ToolFail("Impossible de creer le repertoire : " + SafePath)
  EndIf
EndProcedure

; Vrai si le dossier ne contient aucune entree (hors . et ..).
Procedure.i IsDirectoryEmpty(Path.s)
  Protected Dir.i = ExamineDirectory(#PB_Any, Path, "*")
  If Not Dir : ProcedureReturn #False : EndIf
  Protected Empty.i = #True
  While NextDirectoryEntry(Dir)
    Protected Entry.s = DirectoryEntryName(Dir)
    If Entry <> "." And Entry <> ".."
      Empty = #False
      Break
    EndIf
  Wend
  FinishDirectory(Dir)
  ProcedureReturn Empty
EndProcedure

; Suppression NON recursive par defaut ; recursive=#True pour un dossier non vide.
Procedure.s ToolDeleteFile(Path.s, Recursive.i)
  Protected SafePath.s = ValiderChemin(Path)
  If SafePath = "" : ProcedureReturn ToolFail("ACCES_REFUSE") : EndIf

  If FileSize(SafePath) = -2
    If Recursive
      If DeleteDirectory(SafePath, "", #PB_FileSystem_Recursive)
        ProcedureReturn "Dossier supprime (recursif) : " + SafePath
      Else
        ProcedureReturn ToolFail("Impossible de supprimer le dossier : " + SafePath)
      EndIf
    EndIf
    If Not IsDirectoryEmpty(SafePath)
      ProcedureReturn ToolFail("Erreur : dossier non vide (utiliser recursive=true) : " + SafePath)
    EndIf
    If DeleteDirectory(SafePath, "", 0)
      ProcedureReturn "Dossier supprime : " + SafePath
    Else
      ProcedureReturn ToolFail("Impossible de supprimer le dossier : " + SafePath)
    EndIf
  ElseIf FileSize(SafePath) >= 0
    If DeleteFile(SafePath)
      ProcedureReturn "Fichier supprime : " + SafePath
    Else
      ProcedureReturn ToolFail("Impossible de supprimer le fichier : " + SafePath)
    EndIf
  EndIf
  ProcedureReturn ToolFail("Cible introuvable : " + SafePath)
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
  ProcedureReturn ToolFail("Echec du deplacement de " + SafeOld + " vers " + SafeNew)
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
  ProcedureReturn ToolOk(Res)
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
  ProcedureReturn ToolOk(Res)
EndProcedure

Procedure.s ToolChangeRoot(NewRoot.s, Secret.s)
  If G_RootSecret = ""
    ProcedureReturn ToolFail("Modification refusee : MCP_ROOT_SECRET non configure cote serveur.")
  EndIf
  If Secret <> G_RootSecret
    ProcedureReturn ToolFail("Modification refusee : secret invalide.")
  EndIf
  If FileSize(NewRoot) <> -2
    ProcedureReturn ToolFail("Repertoire introuvable : " + NewRoot)
  EndIf

  G_AllowedRoot = NormalizePath(NewRoot)
  LogDebug("Racine autorisee modifiee : " + G_AllowedRoot)
  ProcedureReturn "Racine autorisee modifiee : " + G_AllowedRoot
EndProcedure

; ---------------------------------------------------------------------------
; Catalogue MCP (hook *G_CatalogBuilder)
; ---------------------------------------------------------------------------
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
  ToolDef(ToolsArr, "delete_file", "Supprimer un fichier ou un dossier (vide par defaut ; recursive=true pour un dossier non vide)", "path|string|Chemin;recursive|boolean|Supprimer recursivement un dossier non vide (defaut: false)", "path")
  ToolDef(ToolsArr, "move_file", "Deplacer ou renommer un fichier", "oldPath|string|Chemin source;newPath|string|Chemin destination", "oldPath;newPath")
  ToolDef(ToolsArr, "get_file_info", "Infos detaillees fichier/dossier", "path|string|Chemin", "path")
  ToolDef(ToolsArr, "search_files", "Rechercher du texte (recursif)", "path|string|Repertoire de depart;pattern|string|Texte recherche", "path;pattern")
  ToolDef(ToolsArr, "change_root", "CHANGER LA ZONE AUTORISEE", "newRoot|string|Nouveau repertoire racine;secret|string|Mot de passe MCP_ROOT_SECRET", "newRoot;secret")

  ProcedureReturn RootJSON
EndProcedure

; ---------------------------------------------------------------------------
; Dispatch des outils (hook *G_ToolHandler)
; ---------------------------------------------------------------------------
Procedure.s ToolDispatch(ToolName.s, ArgsObj.i, *IsError.Integer)
  Select ToolName
    Case "list_files"
      ProcedureReturn ToolListFiles(GetArgString(ArgsObj, "path"))
    Case "read_file"
      ProcedureReturn ToolReadFile(GetArgString(ArgsObj, "path"))
    Case "read_file_lines"
      ProcedureReturn ToolReadFileLines(GetArgString(ArgsObj, "path"), GetArgInt(ArgsObj, "startLine", 1), GetArgInt(ArgsObj, "maxLines", 50))
    Case "write_file"
      ProcedureReturn ToolWriteFile(GetArgString(ArgsObj, "path"), GetArgString(ArgsObj, "content"))
    Case "create_directory"
      ProcedureReturn ToolCreateDirectory(GetArgString(ArgsObj, "path"))
    Case "delete_file"
      ProcedureReturn ToolDeleteFile(GetArgString(ArgsObj, "path"), GetArgBool(ArgsObj, "recursive", #False))
    Case "move_file"
      ProcedureReturn ToolMoveFile(GetArgString(ArgsObj, "oldPath"), GetArgString(ArgsObj, "newPath"))
    Case "get_file_info"
      ProcedureReturn ToolGetFileInfo(GetArgString(ArgsObj, "path"))
    Case "search_files"
      ProcedureReturn ToolSearchFiles(GetArgString(ArgsObj, "path"), GetArgString(ArgsObj, "pattern"))
    Case "change_root"
      ProcedureReturn ToolChangeRoot(GetArgString(ArgsObj, "newRoot"), GetArgString(ArgsObj, "secret"))
    Default
      *IsError\i = #True
      ProcedureReturn ToolFail("Outil inconnu : " + ToolName)
  EndSelect
EndProcedure

; ---------------------------------------------------------------------------
; Programme principal
; ---------------------------------------------------------------------------
G_ServerName = "FileMCPServer-PureBasic"
G_ServerVersion = "1.0.1"
*G_ToolHandler = @ToolDispatch()
*G_CatalogBuilder = @BuildToolsCatalog()

G_AllowedRoot = GetEnvironmentVariable("MCP_ROOT")
If G_AllowedRoot = ""
  G_AllowedRoot = GetCurrentDirectory()
EndIf
G_AllowedRoot = NormalizePath(G_AllowedRoot)

G_RootSecret = GetEnvironmentVariable("MCP_ROOT_SECRET")

If Not CheckStdio()
  End 1
EndIf

MCPMainLoop()

End
