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

-- local trace = lib.trace

local _p1 = (P(1) - S'," \n\t<>') ^ 1
local quoted_file = P'"' * _p1 * P'"'
local unquoted_file = _p1
local _p2 = loc.digit ^ 1
local _s = P"s" ^ -1

local p1 = S" \t" ^ 0 * P"File " * (quoted_file + unquoted_file)
            * P", line" * _s * P" " * _p2 * (P"-" * _p2) ^ -1
            * (P(-1) + P"," * (P" character" * _s * P" " * _p2 * (P"-" * _p2) ^ -1 * P":") ^ -1)

quoted_file = P'"' * wrapper(_p1, "file") * P'"'
unquoted_file = wrapper(_p1, "file")
local line = wrapper(_p2, "line")
local line_end = wrapper(_p2, "line_end")
local col = wrapper(_p2, "col")
local col_end = wrapper(_p2, "col_end")

local p2 = CT(S" \t" ^ 0 * P"File " * pos("b") * (quoted_file + unquoted_file)
            * P", line" * _s * P" " * line * (P"-" * line_end) ^ -1
            * (P(-1) + #P('\n') + P"," * (P" character" * _s * P" " * col * (P"-" * col_end) ^ -1 * P":") ^ -1)
            * (S" \n" * wrapper(P"Warning" * CC(level.WARNING), "type_hl") * (P" " * _p2) ^ -1 * P":") ^ -1 * pos("e")) / function(t)
                if t.type_hl then
                    t.type = t.type_hl.c
                    t.type_hl.c = nil
                    t.type_hl.hl = constants.get_hl_by_severity(t.type)
                end
                return t
            end

return { multiline = 2, opt_multiline = true, pattern = p1, pattern2 = p2, highlights = { "type_hl" } }
