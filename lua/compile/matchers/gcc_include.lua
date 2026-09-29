local constants = require("compile.constants")
local level = constants.Severity
local lib = require("compile.matchers")
local pos = lib.pos
local wrapper = lib.wrapper
local lpeg = vim.lpeg
local loc = lpeg.locale()
local P = lpeg.P
local S = lpeg.S
local CC = lpeg.Cc
local CT = lpeg.Ct
local CG = lpeg.Cg

local _end = S":," * P(-1)
local line = wrapper(loc.digit ^ 1, "line")
local col = wrapper(loc.digit ^ 1, "col")
local pos_end = P":" * line * (P":" * col) ^ -1 * _end
local file = wrapper((P(1) - pos_end) ^ 1, "file")
local type = CG(CC(level.INFO), "type")
local head = (P"In file included " + P"                 " + P"\t") * P"from "

local p = CT(pos("b") * head * file * pos_end * type * pos("e"))

return { multiline = 1, pattern = p }

