; ============================================================================
;  fileMCP_Linux.pbi  -  Include project pour LINUX (x64 / ARM64)
; ============================================================================
;  Usage : dans l'IDE PureBasic, Ouvrir ce fichier (.pbi) puis Compiler (F5).
;  Il importe le source commun fileMCP.pb avec les options de compilation
;  propres a Linux.
; ----------------------------------------------------------------------------
;  NOTE TRANSPARENCE : le lien depuis cet environnement herberge ne peut pas
;  verifier la syntaxe exacte des sections [SECTION] du format .pbi (le site
;  purebasic.com etait inaccessible lors de la generation). Le contenu ci-
;  dessous suit le format standard connu des projets PureBasic (PB 6.x).
;  Si l'IDE refuse le fichier, solution de repli manuelle equivalente :
;    1) Ouvrir fileMCP.pb dans l'IDE
;    2) Options du compilateur -> Format : Console
;    3) Nom de l'executable : filemcp-linux
;    4) Compilation -> Compiler
; ============================================================================

[PROJECT]
ID = PBFileMCP.Linux
Editor = 1000,1000,900,700,0
Compiler = 1,0,0,0,"/tmp/filemcp",""
Debugger = 0,0

[X]
EnableExplicit = 1
ExecutableType = 1          ; Console
Architecture = 0            ; par defaut (x64 sur x64, ARM64 sur ARM64 Apple)
DPIAware = 1
Threaded = 1

[FILE]
fileMCP.pb

[CARET]
CursorPosition = 1,1
