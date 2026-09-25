local lib = require("compile.matchers")
local pos = lib.pos
local wrapper = lib.wrapper
local hl_wrapper = lib.hl_wrapper
local lpeg = vim.lpeg
local loc = lpeg.locale()
local P = lpeg.P
local CT = lpeg.Ct

local _eos = -P(1)  -- end of string

local line = wrapper(loc.digit ^ 1, "line")
local col = wrapper(loc.digit ^ 1, "col")
local location = ":" * line * ":" * col * ":" * _eos
local file = wrapper((P(1) - #location) ^ 1, "file")
local _link = file * location
local link = pos("t_b") * _link * pos("t_e")

local space4 = P" " * P" " * P" " * P" "

local _p = P"' " * (P"(" * loc.digit ^ 1 * P") ") ^ -1
    * hl_wrapper(P"panicked", "CompileLuaError", "panic") * P" at " * link
local p = CT(pos("b") * space4 ^ -1 * P"thread '" * (P(1) - #_p) ^ 1 * _p * pos("e")) / function(t)
    t.link = { b = t.t_b, e = t.t_e }
    t.t_b = nil
    t.t_e = nil

    return t
end

return { multiline = 1, pattern = p, highlights = { "panic" } }
