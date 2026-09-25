-- GNU make
local level = require("compile.constants").Severity
local lib = require("compile.matchers")
local pos = lib.pos
local wrapper = lib.wrapper
local lpeg = vim.lpeg
local loc = lpeg.locale()
local P = lpeg.P
local CT = lpeg.Ct

local line = wrapper(loc.digit ^ 1, "line")
local _p = P":" * line
local file = wrapper((P(1) - #_p) ^ 1, "file")
local cap = P": *** [" * pos("t_b") * file * P":" * line * ":" * (P(1) - #P"]") ^ 1 * pos("t_e") * P"]"
local p = (P(1) - #cap) ^ 1 * CT(pos("b") * cap * pos("e")) / function(t)
    t.link = { b = t.t_b, e = t.t_e }
    t.t_b = nil
    t.t_e = nil
    t.type = level.INFO
    return t
end

return { multiline = 1, pattern = p }
