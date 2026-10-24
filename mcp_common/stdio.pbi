; ============================================================================
;  stdio.pbi - Couche E/S stdio multi-plateforme (Windows / Linux / macOS)
;  Partagee par tous les serveurs MCP du depot.
; ============================================================================
;  - Lecture stdin : fiable en mode pipe, gere proprement l'EOF sur les
;    3 OS ; Input() est banni car non fiable en mode pipe.
;  - Ecriture stdout :
;       * Windows -> WriteFile(GetStdHandle(STD_OUTPUT_HANDLE))
;                    + FlushFileBuffers (mode pipe/stdio MCP)
;       * Linux/macOS -> write_() sur le descripteur 1 + fflush_(0)
;  - Ecriture stderr : idem sur la sortie d'erreur (jamais sur stdout,
;    pour ne pas corrompre le flux MCP) -> voir SendStderrLine().
; ============================================================================
;  A inclure en premier dans chaque serveur :
;    IncludeFile "../mcp_common/stdio.pbi"
; ============================================================================

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #C_STD_INPUT_HANDLE  = -10
  #C_STD_OUTPUT_HANDLE = -11
  #C_STD_ERROR_HANDLE  = -12

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

; ---------------------------------------------------------------------------
; Ecriture d'une ligne sur stdout (flux MCP)
; ---------------------------------------------------------------------------
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

; ---------------------------------------------------------------------------
; Ecriture d'une ligne sur stderr (logs, diagnostics : JAMAIS sur stdout)
; ---------------------------------------------------------------------------
Procedure SendStderrLine(Text.s)
  Protected OutText.s = Text + #LF$
  Protected Size.i = StringByteLength(OutText, #PB_UTF8)
  If Size = 0 : ProcedureReturn : EndIf

  Protected *Mem = AllocateMemory(Size)
  If *Mem
    PokeS(*Mem, OutText, -1, #PB_UTF8 | #PB_String_NoZero)
    CompilerIf #PB_Compiler_OS = #PB_OS_Windows
      Protected hErr.i = Std_GetHandle(#C_STD_ERROR_HANDLE)
      Protected WrittenLow.l = 0
      Std_WriteFile(hErr, *Mem, Size, @WrittenLow, #Null)
    CompilerElse
      write_(2, *Mem, Size)
    CompilerEndIf
    FreeMemory(*Mem)
  EndIf
EndProcedure

; ---------------------------------------------------------------------------
; Verifier que la couche E/S stdio est bien chargee (kernel32 sous Windows)
; ---------------------------------------------------------------------------
Procedure.i CheckStdio()
  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    If hKernel32 = 0 Or Std_GetHandle = 0 Or Std_ReadFile = 0 Or Std_WriteFile = 0
      ProcedureReturn #False
    EndIf
  CompilerEndIf
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Lecture stdin bufferisee (une ligne JSON-RPC par ligne)
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

; Retourne "" sur EOF reel (fin de flux stdin) ; G_EOF est positionne
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
