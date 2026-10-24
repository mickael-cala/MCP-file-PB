EnableExplicit
OpenConsole()
IncludeFile "../mcp_common/stdio.pbi"
IncludeFile "../mcp_common/logging.pbi"
IncludeFile "../mcp_common/json_helpers.pbi"
IncludeFile "../src/context7_core.pbi"
Define st.Integer
Define body.s = C7HttpGet("https://context7.com/api/v1/search?query=react&libraryType=oss", "", 15, @st)
PrintN("status=" + Str(st\i) + " len=" + Str(Len(body)))
