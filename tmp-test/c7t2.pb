EnableExplicit
OpenConsole()
IncludeFile "../mcp_common/stdio.pbi"
IncludeFile "../mcp_common/logging.pbi"
IncludeFile "../mcp_common/json_helpers.pbi"
IncludeFile "../src/context7_core.pbi"
PrintN(Left(ToolResolveLibraryId("react", "oss"), 200))
