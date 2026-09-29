local lib = require("compile.matchers")
local pos = lib.pos
local wrapper = lib.wrapper
local lpeg = vim.lpeg
local loc = lpeg.locale()
local P = lpeg.P
local S = lpeg.S
local CT = lpeg.Ct

local _line = loc.digit ^ 1
local _end = P": " * P(1) ^ 1 * P(-1)
local _line_end = P":" * _line * _end
local _file = (P(1) - #_line_end) ^ 1
local _head = (P(1) - #(S"\t\n" + (P": " * #_file))) ^ 1
local p1 = _head * P": " * _file * _line_end

local line = wrapper(loc.digit ^ 1, "line")
local static_rest = P"\nstack traceback:\n\t"
local rest = P": " * (P(1) - #static_rest) ^ 1 * static_rest
local file = wrapper((P(1) - #(P":" * line * rest)) ^ 1, "file")
local head = (P(1) - (S"\t\n" + #(P": " * file))) ^ 1
local p2 = CT(pos("b") * head * P": " * file * P":" * line * rest * pos("e")) / function(t)
    t.link = { b = t.file.b, e = t.line.e }
    return t
end

return { multiline = 3, pattern = p1, pattern2 = p2 }
