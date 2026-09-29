local level = require("compile.constants").Severity
local lib = require("compile.matchers")
local pos = lib.pos
local wrapper = lib.wrapper
local lpeg = vim.lpeg
local loc = lpeg.locale()
local P = lpeg.P
local S = lpeg.S
local CT = lpeg.Ct

local _end = P": in "
local line = wrapper(loc.digit ^ 1, "line")
local line_end = (P":" * line) ^ -1 * _end
local file = wrapper((P(1) - #(S"\t\n" + line_end)) ^ 1, "file")

local p = CT(P"\t" * pos("b") * (P"[C]: in " + file * line_end) * pos("e")) / function(t)
    if t.file then
        t.link = { b = t.file.b, e = t.line and t.line.e or t.file.e }
    end
    t.type = level.INFO
    return t
end

return { multiline = 1, pattern = p }
