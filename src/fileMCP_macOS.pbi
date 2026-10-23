; ============================================================================
;  fileMCP_macOS.pbi  -  Include project pour macOS (ARM64 Apple Silicon
;                        et x64 Intel)
; ============================================================================
;  Usage : dans l'IDE PureBasic (sous macOS), Ouvrir ce fichier (.pbi) puis
;  Compiler (F5). Le chemin POSIX ('/') et les appels read_/write_/fflush_
;  sont selectionnes automatiquement par les CompilerIf de fileMCP.pb.
; ----------------------------------------------------------------------------
;  NOTE TRANSPARENCE : voir le meme avertissement de format que pour le .pbi
;  Linux (lien non verifiable ici). Repli manuel si besoin :
;    1) Ouvrir fileMCP.pb sous macOS dans l'IDE
;    2) Options du compilateur -> Format : Console
;    3) Nom de l'executable : filemcp-macos
;    4) Compilation -> Compiler
; ============================================================================

[PROJECT]
ID = PBFileMCP.macOS
Editor = 1000,1000,900,700,0
Compiler = 1,0,0,0,"/tmp/filemcp-macos",""
Debugger = 0,0

[X]
EnableExplicit = 1
ExecutableType = 1          ; Console
Architecture = 0            ; natif (ARM64 sur Apple Silicon, x64 sur Intel)
DPIAware = 1
Threaded = 1

[FILE]
fileMCP.pb

[CARET]
CursorPosition = 1,1
