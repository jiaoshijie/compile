local lib = require("compile.matchers")
local pos = lib.pos
local wrapper = lib.wrapper
local lpeg = vim.lpeg
local loc = lpeg.locale()
local P = lpeg.P
local S = lpeg.S
local CT = lpeg.Ct

local file = wrapper((P(1) - S": \t") ^ 1, "file")
local line = wrapper(loc.digit ^ 1, "line")

local p = CT(pos("b") * file * P": line " * line * P":" * pos("e"))

return { multiline = 1, pattern = p }
