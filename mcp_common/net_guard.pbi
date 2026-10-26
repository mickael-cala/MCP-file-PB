; ============================================================================
;  net_guard.pbi - Validation d'adresse reseau (anti-SSRF)
;  Partage par les serveurs qui recuperent des URL distantes.
; ============================================================================
;  Principe : un nom d'hote n'est jamais juge sur sa chaine. Il est resolu
;  (getaddrinfo) et CHAQUE adresse retournee doit etre globale (publique).
;  Toute erreur de resolution est un refus (fail-closed).
;
;  A inclure avant le serveur qui l'utilise :
;    IncludeFile "../mcp_common/net_guard.pbi"
; ============================================================================

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  ImportC "ws2_32.lib"
    getaddrinfo(hostname.i, servname.i, hints.i, *res)
    freeaddrinfo(*res)
    WSAStartup(wVersion.w, *lpWSAData)
  EndImport
  #NG_AF_INET6 = 23
CompilerElse
  ImportC ""
    getaddrinfo(hostname.i, servname.i, hints.i, *res)
    freeaddrinfo(*res)
  EndImport
  #NG_AF_INET6 = 10
CompilerEndIf

; Offsets des champs de struct addrinfo, selon OS et architecture.
CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  CompilerIf #PB_Compiler_Processor = #PB_Processor_x64
    #NG_AI_ADDR = 32
    #NG_AI_NEXT = 40
  CompilerElse
    #NG_AI_ADDR = 24
    #NG_AI_NEXT = 28
  CompilerEndIf
CompilerElse
  CompilerIf #PB_Compiler_Processor = #PB_Processor_x64
    #NG_AI_ADDR = 24
    #NG_AI_NEXT = 40
  CompilerElse
    #NG_AI_ADDR = 20
    #NG_AI_NEXT = 28
  CompilerEndIf
CompilerEndIf

; ---------------------------------------------------------------------------
; Initialisation Winsock (une seule fois)
; ---------------------------------------------------------------------------
CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  Global G_NG_WsaReady.i = 0

  Procedure.i NetGuardWsaInit()
    If G_NG_WsaReady : ProcedureReturn #True : EndIf
    Protected *Wsa = AllocateMemory(512)
    If *Wsa = 0 : ProcedureReturn #False : EndIf
    If WSAStartup($0202, *Wsa) = 0
      G_NG_WsaReady = #True
    EndIf
    FreeMemory(*Wsa)
    ProcedureReturn G_NG_WsaReady
  EndProcedure
CompilerEndIf

; ---------------------------------------------------------------------------
; Classification IPv4 (fonction pure, testable)
; ---------------------------------------------------------------------------
Procedure.i NetGuardIPv4IsGlobal(A.i, B.i, C.i, D.i)
  If A <= 0 Or A >= 224 : ProcedureReturn #False : EndIf        ; 0/8, multicast, reserve
  If A = 10 : ProcedureReturn #False : EndIf                     ; 10/8
  If A = 127 : ProcedureReturn #False : EndIf                    ; loopback
  If A = 169 And B = 254 : ProcedureReturn #False : EndIf        ; link-local / metadata
  If A = 172 And B >= 16 And B <= 31 : ProcedureReturn #False : EndIf
  If A = 192 And B = 168 : ProcedureReturn #False : EndIf        ; 192.168/16
  If A = 100 And B >= 64 And B <= 127 : ProcedureReturn #False : EndIf ; CGNAT
  If A = 192 And B = 0 And C = 0 : ProcedureReturn #False : EndIf      ; 192.0.0/24
  If A = 192 And B = 0 And C = 2 : ProcedureReturn #False : EndIf      ; TEST-NET-1
  If A = 192 And B = 88 And C = 99 : ProcedureReturn #False : EndIf    ; 6to4 relay
  If A = 198 And B >= 18 And B <= 19 : ProcedureReturn #False : EndIf  ; 198.18/15
  If A = 198 And B = 51 And C = 100 : ProcedureReturn #False : EndIf   ; TEST-NET-2
  If A = 203 And B = 0 And C = 113 : ProcedureReturn #False : EndIf    ; TEST-NET-3
  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Classification IPv6 (*Addr pointe sur 16 octets)
; ---------------------------------------------------------------------------
Procedure.i NetGuardIPv6IsGlobal(*Addr)
  If *Addr = 0 : ProcedureReturn #False : EndIf
  Protected i.i, AllZero.i = #True
  For i = 0 To 15
    If (PeekB(*Addr + i) & $FF) <> 0
      AllZero = #False
      Break
    EndIf
  Next
  If AllZero : ProcedureReturn #False : EndIf                    ; ::

  Protected B0.i = PeekB(*Addr) & $FF
  Protected B1.i = PeekB(*Addr + 1) & $FF
  Protected B10.i = PeekB(*Addr + 10) & $FF
  Protected B11.i = PeekB(*Addr + 11) & $FF

  ; ::1 (loopback)
  If (B0 = 0) And (B1 = 0) And (PeekB(*Addr + 15) & $FF) = 1
    Protected OnlyLast.i = #True
    For i = 2 To 14
      If (PeekB(*Addr + i) & $FF) <> 0 : OnlyLast = #False : Break : EndIf
    Next
    If OnlyLast : ProcedureReturn #False : EndIf
  EndIf

  If (B0 & $FE) = $FC : ProcedureReturn #False : EndIf            ; fc00::/7 ULA
  If B0 = $FE And (B1 & $C0) = $80 : ProcedureReturn #False : EndIf ; fe80::/10
  If B0 = $FF : ProcedureReturn #False : EndIf                    ; ff00::/8 multicast
  If B0 = $20 And B1 = $01 And (PeekB(*Addr + 2) & $FF) = $0D And (PeekB(*Addr + 3) & $FF) = $B8
    ProcedureReturn #False                                        ; 2001:db8::/32
  EndIf

  ; IPv4-mappee ::ffff:a.b.c.d
  If (B10 = $FF) And (B11 = $FF)
    Protected PrefixZero.i = #True
    For i = 0 To 9
      If (PeekB(*Addr + i) & $FF) <> 0 : PrefixZero = #False : Break : EndIf
    Next
    If PrefixZero
      ProcedureReturn NetGuardIPv4IsGlobal(PeekB(*Addr + 12) & $FF, PeekB(*Addr + 13) & $FF, PeekB(*Addr + 14) & $FF, PeekB(*Addr + 15) & $FF)
    EndIf
  EndIf

  ; IPv4-compatible ::a.b.c.d (depreciee mais encore acceptee par certaines piles)
  Protected CompatZero.i = #True
  For i = 0 To 11
    If (PeekB(*Addr + i) & $FF) <> 0 : CompatZero = #False : Break : EndIf
  Next
  If CompatZero
    ProcedureReturn NetGuardIPv4IsGlobal(PeekB(*Addr + 12) & $FF, PeekB(*Addr + 13) & $FF, PeekB(*Addr + 14) & $FF, PeekB(*Addr + 15) & $FF)
  EndIf

  ProcedureReturn #True
EndProcedure

; ---------------------------------------------------------------------------
; Resolution + validation de TOUTES les adresses d'un hote
; ---------------------------------------------------------------------------
Procedure.i NetGuardHostIsGlobal(Host.s)
  Host = Trim(Host)
  If Host = "" : ProcedureReturn #False : EndIf

  CompilerIf #PB_Compiler_OS = #PB_OS_Windows
    If Not NetGuardWsaInit() : ProcedureReturn #False : EndIf
  CompilerEndIf

  Protected *H = AllocateMemory(StringByteLength(Host, #PB_Ascii) + 1)
  If *H = 0 : ProcedureReturn #False : EndIf
  PokeS(*H, Host, -1, #PB_Ascii)

  Protected *Res = 0
  Protected Rc.i = getaddrinfo(*H, 0, 0, @*Res)
  FreeMemory(*H)
  If Rc <> 0 Or *Res = 0
    If *Res : freeaddrinfo(*Res) : EndIf
    ProcedureReturn #False                    ; fail-closed
  EndIf

  Protected *Cur = *Res
  Protected AllGlobal.i = #True
  Protected Count.i = 0

  While *Cur <> 0
    Count + 1
    Protected Family.i = PeekL(*Cur + 4)
    Protected *Sa = PeekI(*Cur + #NG_AI_ADDR)
    If *Sa = 0
      AllGlobal = #False
    ElseIf Family = 2
      If Not NetGuardIPv4IsGlobal(PeekB(*Sa + 4) & $FF, PeekB(*Sa + 5) & $FF, PeekB(*Sa + 6) & $FF, PeekB(*Sa + 7) & $FF)
        AllGlobal = #False
      EndIf
    ElseIf Family = #NG_AF_INET6
      If Not NetGuardIPv6IsGlobal(*Sa + 8)
        AllGlobal = #False
      EndIf
    Else
      AllGlobal = #False
    EndIf
    *Cur = PeekI(*Cur + #NG_AI_NEXT)
  Wend

  freeaddrinfo(*Res)
  If Count = 0 : ProcedureReturn #False : EndIf
  ProcedureReturn AllGlobal
EndProcedure

; ---------------------------------------------------------------------------
; Validation d'URL http/https (retourne "" si refusee)
; ---------------------------------------------------------------------------
Procedure.s NetGuardValidateUrl(Url.s)
  Protected U.s = Trim(Url)
  If U = "" : ProcedureReturn "" : EndIf

  Protected Scheme.s = LCase(GetURLPart(U, #PB_URL_Protocol))
  If Scheme <> "http" And Scheme <> "https" : ProcedureReturn "" : EndIf

  Protected Host.s = Trim(GetURLPart(U, #PB_URL_Site))
  ; userinfo eventuel (user:pass@host)
  Protected At.i = FindString(Host, "@")
  If At > 0 : Host = Mid(Host, At + 1) : EndIf
  ; IPv6 litterale entre crochets
  If Left(Host, 1) = "[" And Right(Host, 1) = "]"
    Host = Mid(Host, 2, Len(Host) - 2)
  EndIf
  If Host = "" : ProcedureReturn "" : EndIf

  If Not NetGuardHostIsGlobal(Host) : ProcedureReturn "" : EndIf
  ProcedureReturn U
EndProcedure

; ---------------------------------------------------------------------------
; Resolution d'une cible de redirection relative a une URL de base
; ---------------------------------------------------------------------------
Procedure.s NetGuardResolveLocation(BaseUrl.s, Location.s)
  Protected Loc.s = Trim(Location)
  If Loc = "" : ProcedureReturn "" : EndIf

  Protected Scheme.s = LCase(GetURLPart(BaseUrl, #PB_URL_Protocol))

  If LCase(Left(Loc, 7)) = "http://" Or LCase(Left(Loc, 8)) = "https://"
    ProcedureReturn Loc
  EndIf
  If Left(Loc, 2) = "//"
    ProcedureReturn Scheme + ":" + Loc
  EndIf
  If Left(Loc, 1) = "/"
    ProcedureReturn Scheme + "://" + GetURLPart(BaseUrl, #PB_URL_Site) + Loc
  EndIf

  ; Chemin relatif : reprendre le repertoire de l'URL de base
  Protected Path.s = GetURLPart(BaseUrl, #PB_URL_Path)
  Protected Slash.i = Len(Path)
  While Slash > 0
    If Mid(Path, Slash, 1) = "/" : Break : EndIf
    Slash - 1
  Wend
  If Slash > 0 : Path = Left(Path, Slash) : Else : Path = "/" : EndIf

  ProcedureReturn Scheme + "://" + GetURLPart(BaseUrl, #PB_URL_Site) + Path + Loc
EndProcedure
