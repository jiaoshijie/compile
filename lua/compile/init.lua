local _M = {}

--- @param cmd string
--- @param buf_name string?
--- @param cfg table
_M.compile = function(cmd, buf_name, cfg)
    require("compile.runtime").compile(cmd, buf_name, cfg)
end

_M.norm_ro = function(bufnr, cfg)
    require("compile.runtime").norm(true, bufnr, cfg)
end

_M.norm_rw = function(bufnr, cfg)
    require("compile.runtime").norm(false, bufnr, cfg)
end

_M.ls = function()
    require("compile.runtime").ls()
end

_M.statusline = function(winid)
    return require("compile.runtime").statusline(winid)
end

return _M
