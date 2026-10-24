EnableExplicit
OpenConsole()
PrototypeC whttpOpen(a.s, b.i, c.i, d.i, e.i)
PrototypeC whttpConnect(a.i, b.s, c.i, d.i)
PrototypeC whttpOpenRequest(a.i, b.s, c.s, d.i, e.i, f.i, g.i)
PrototypeC whttpSendRequest(a.i, b.i, c.i, d.i, e.i, f.i, g.i)
PrototypeC whttpReceiveResponse(a.i, b.i)
PrototypeC whttpQueryHeaders(a.i, b.i, c.i, d.i, e.i, f.i)
PrototypeC whttpQueryDataAvailable(a.i, b.i)
PrototypeC whttpReadData(a.i, b.i, c.i, d.i)
PrototypeC whttpCloseHandle(a.i)

Global hL.i = OpenLibrary(#PB_Any, "winhttp.dll")
Global pOpen.whttpOpen = GetFunction(hL, "WinHttpOpen")
Global pConn.whttpConnect = GetFunction(hL, "WinHttpConnect")
Global pReq.whttpOpenRequest = GetFunction(hL, "WinHttpOpenRequest")
Global pSend.whttpSendRequest = GetFunction(hL, "WinHttpSendRequest")
Global pRecv.whttpReceiveResponse = GetFunction(hL, "WinHttpReceiveResponse")
Global pQH.whttpQueryHeaders = GetFunction(hL, "WinHttpQueryHeaders")
Global pAv.whttpQueryDataAvailable = GetFunction(hL, "WinHttpQueryDataAvailable")
Global pRd.whttpReadData = GetFunction(hL, "WinHttpReadData")
Global pCl.whttpCloseHandle = GetFunction(hL, "WinHttpCloseHandle")

Define hs.i = pOpen("test/1.0", 0, 0, 0, 0)
Define hc.i = pConn(hs, "context7.com", 443, 0)
Define hr.i = pReq(hc, "GET", "/api/v1/search?query=react&libraryType=oss", 0, 0, 0, $00800000)
PrintN("open=" + Str(hs) + " conn=" + Str(hc) + " req=" + Str(hr))
PrintN("send=" + Str(pSend(hr, 0, 0, 0, 0, 0, 0)))
PrintN("recv=" + Str(pRecv(hr, 0)))
Define code.i = 0
Define clen.i = 4
Define ok.i = pQH(hr, 19 | $20000000, 0, @code, @clen, 0)
PrintN("qh ok=" + Str(ok) + " code=" + Str(code) + " clen=" + Str(clen))
Define avail.i = 0, rd.i = 0, body.s = ""
Define *b = AllocateMemory(65536)
While pAv(hr, @avail)
  If avail <= 0 : Break : EndIf
  rd = 0
  If pRd(hr, *b, avail, @rd) = 0 Or rd <= 0 : Break : EndIf
  body + PeekS(*b, rd, #PB_UTF8 | #PB_ByteLength)
Wend
PrintN("len=" + Str(Len(body)))
pCl(hr) : pCl(hc) : pCl(hs)
