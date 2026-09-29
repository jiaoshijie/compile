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

local _extra_E = P("[E") * loc.digit ^ 4 * "]"
local _eos = -P(1)  -- end of string
local _any_nl = P(1) - '\n'

local typ_raw = (P"error" * _extra_E ^ -1 + P"warning" + P"note") * ":"
local typ = wrapper(P"error" * _extra_E ^ -1 * CC(level.ERROR)
                + P"warning" * CC(level.WARNING)
                + P"note" * CC(level.INFO) , "type_hl")

local line = wrapper(loc.digit ^ 1, "line")
local col = wrapper(loc.digit ^ 1, "col")
local location = ":" * line * ":" * col * _eos
local file = wrapper((P(1) - #location) ^ 1, "file")
local p1 = typ_raw
local p2 = CT(pos("b") * typ * ":" * _any_nl ^ 1 * '\n --> ' * file * location * pos("e")) / function(t)
    t.link = { b = t.file.b, e = t.col.e }
    t.type = t.type_hl.c
    t.type_hl.c = nil
    t.type_hl.hl = constants.get_hl_by_severity(t.type)
    return t
end

return { multiline = 2, pattern = p1, pattern2 = p2, highlights = { "type_hl" } }
