local lib = require("compile.matchers")
local pos = lib.pos
local wrapper = lib.wrapper
local lpeg = vim.lpeg
local loc = lpeg.locale()
local P = lpeg.P
local S = lpeg.S
local CT = lpeg.Ct

local _end = S",." + P(-1) + P" during global destruction." * P(-1)
local line = wrapper(loc.digit ^ 1, "line")
local line_end = P" line " * line * _end
local file = wrapper((P(1) - #line_end) ^ 1, "file")

local p = CT(pos("b") * P" at " * file * line_end * pos("e"))

-- NOTE: this pattern seems can not at the beginning of the line
local search = (P(1) - #p) ^ 1 * p

return { multiline = 1, pattern = search }
