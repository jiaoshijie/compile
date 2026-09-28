local lib = require("compile.matchers")
local pos = lib.pos
local wrapper = lib.wrapper
local lpeg = vim.lpeg
local loc = lpeg.locale()
local P = lpeg.P
local CT = lpeg.Ct

local line = P" line " * wrapper(loc.digit ^ 1, "line") * P":" * P(-1)
local file = wrapper((P(1) - #line) ^ 1, "file")
local p = CT(pos("b") * P"In " * file * line * pos("e"))

return { multiline = 1, pattern = p }
