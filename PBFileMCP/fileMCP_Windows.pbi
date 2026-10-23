; ============================================================================
;  fileMCP_Windows.pbi  -  Include project pour WINDOWS (x64)
; ============================================================================
;  Usage : dans l'IDE PureBasic (sous Windows), Ouvrir ce fichier (.pbi)
;  puis Compiler (F5). Le code E/S stdio est automatiquement selectionne en
;  mode Win32 (GetStdHandle_ / WriteFile_ / FlushFileBuffers_) via les
;  directives CompilerIf #PB_Compiler_OS deja presentes dans fileMCP.pb.
; ----------------------------------------------------------------------------
;  NOTE TRANSPARENCE : voir le meme avertissement de format que pour le .pbi
;  Linux (lien non verifiable ici). Repli manuel si besoin :
;    1) Ouvrir fileMCP.pb sous Windows dans l'IDE
;    2) Options du compilateur -> Format : Console
;    3) Nom de l'executable : filemcpserver.exe
;    4) Compilation -> Compiler
; ============================================================================

[PROJECT]
ID = PBFileMCP.Windows
Editor = 1000,1000,900,700,0
Compiler = 1,0,0,0,"C:\PureBasic\filemcpserver.exe",""
Debugger = 0,0

[X]
EnableExplicit = 1
ExecutableType = 1          ; Console
SubSystem = 0               ; Console (pas GUI)
Unicode = 1
DPIAware = 1
Threaded = 1
XP = 1

[FILE]
fileMCP.pb

[CARET]
CursorPosition = 1,1
