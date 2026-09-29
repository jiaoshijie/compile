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

local _end = P" (" * (P(1) - P")") ^ 1 * P"):" * P(-1)
local line = wrapper(loc.digit ^ 1, "line")
local line_end = P":" * line * _end
local file = wrapper((P(1) - line_end) ^ 1, "file")
local type = wrapper((P"Error" * CC(level.ERROR) + P"Warning" * CC(level.WARNING)), "type_hl")

local p = CT(pos("b") * P"CMake " * type * P" at " * file * line_end * pos("e")) / function(t)
    t.type = t.type_hl.c
    t.type_hl.c = nil
    t.type_hl.hl = constants.get_hl_by_severity(t.type)
    return t
end

return { multiline = 1, pattern = p, highlights = { "type_hl" } }
