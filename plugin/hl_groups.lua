local highlights = {
    CompileLuaSep       = { default = true, link = "Conceal" },
    CompileLuaHint      = { default = true, link = "Label" },
    CompileLuaInfo      = { default = true, link = "Added" },
    CompileLuaWarning   = { default = true, link = "Changed" },
    CompileLuaError     = { default = true, link = "Removed" },
    CompileLuaLnum      = { default = true, link = "CursorLineNr" },
    CompileLuaCol       = { default = true, link = "ColorColumn" },
    CompileLuaLink      = { default = true, underline = true },
    CompileLuaAttention = { default = true, link = "IncSearch" },
    CompileLuaGrepMatch = { default = true, link = "Label" },
}

for k, v in pairs(highlights) do
    vim.api.nvim_set_hl(0, k, v)
end
