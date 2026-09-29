local constants = require("compile.constants")
local level = constants.Severity
local lib = require("compile.matchers")
local pos = lib.pos
local wrapper = lib.wrapper
local lpeg = vim.lpeg
local loc = lpeg.locale()
local P = lpeg.P
local CC = lpeg.Cc
local CT = lpeg.Ct
local CG = lpeg.Cg

local _end = P":" * P(-1)
local line = wrapper(loc.digit ^ 1, "line")
local line_end = P":" * line * _end
local file = wrapper((P(1) - line_end) ^ 1, "file")
local type = CG(CC(level.INFO), "type")

local p = CT(pos("b") * P"In file included from " * file * line_end * type * pos("e"))

return { multiline = 1, pattern = p }
