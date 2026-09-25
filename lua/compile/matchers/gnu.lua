-- The `gnu' message syntax is
--   [PROGRAM:]FILE:LINE[-ENDLINE][:COL[-ENDCOL]]: MESSAGE
-- or
--   [PROGRAM:]FILE:LINE[.COL][-ENDLINE[.ENDCOL]]: MESSAGE

local level = require("compile.constants").Severity
local lib = require("compile.matchers")
local pos = lib.pos
local wrapper = lib.wrapper
local lpeg = vim.lpeg
local loc = lpeg.locale()
local P = lpeg.P
local S = lpeg.S
local CC = lpeg.Cc
local CG = lpeg.Cg
local CT = lpeg.Ct


-- 1. severity part
-- ` MESSAGE`
local _p11 = P(1) - (loc.digit + P":")
local _p12 = P(1) - loc.digit
local _warning = (P" " ^ 0 * (P"FutureWarning" + P"RuntimeWarning" + P"warning" + (P"W" * (P":" + P"arning")))) * CC(level.WARNING)
local _info = (P" " ^ 0 * (S"Nn" * P"ote" + P"required from"
              + P"I" * (P":" + P"nfo" * (P"rmation" * P"al" ^ -1) ^ -1)
              + P"in" * (P"stantiated from" + P"fo" * (P"rmation" * P"al" ^ -1) ^ -1)
              + P"[ skipping " * (P(1) - #P" ]") ^ 1 * P" ]")) * CC(level.INFO)
local _error = (P" " ^ 0 * S"Ee" * P"rror"
               + loc.digit * (_p11 + (loc.digit ^ 2 * (#(P(1) - P":") + P(-1))))
               + P(-1) + _p12) * CC(level.ERROR)
local typ_part = CG(_warning + _info + _error, "type")

-- 2. line and col parts
-- `LINE[-ENDLINE][:COL[-ENDCOL]]`
-- `LINE[.COL][-ENDLINE[.ENDCOL]]`
--[[
LINE

_p23
LINE-ENDLINE
LINE-ENDLINE:COL
LINE-ENDLINE.ENDCOL

NOTE: This one can not be parsed correctly,
      because of the supporting of program part parsing
      But this seems also not a format that gnu tools will generate, as
      the compile.el also can't parse this format correctly.
      So I think it is OK to not try to parse it.
LINE-ENDLINE:COL-ENDCOL

_p21
LINE:COL
LINE:COL-ENDCOL

_p24
LINE.COL
LINE.COL-ENDLINE
LINE.COL-ENDLINE.ENDCOL
--]]
local _line = wrapper(loc.digit ^ 1, "line")
local _eline = wrapper(loc.digit ^ 1, "line_end")
local _col = wrapper(loc.digit ^ 1, "col")
local _ecol = wrapper(loc.digit ^ 1, "col_end")
local _p21 = (P":" - #(P":" * #typ_part)) * _col  * (P"-" * _ecol) ^ -1
local _p22 = P"-" * _eline * (P"." * _ecol) ^ -1
local _p23 = P"-" * _eline * (_p21 + (P"." * _ecol)) ^ -1
local _p24 = P"." * _col * _p22 ^ -1
local pos_part = _line * (_p23 + _p24 + _p21) ^ -1

-- `:LINE[-ENDLINE][:COL[-ENDCOL]]: MESSAGE`
local pos_typ_part = P":" * pos_part * P":" * typ_part

-- 3. file name
-- `FILE`
local _p1 = P(1) - (S"\t " + loc.digit)
local _p2 = loc.digit ^ 1 * (P(1) - loc.digit)
local _p3 = P(1) - S" :"
local _p4 = P(1) - S"/-"
local _p5 = P(1) - P" "
local file_part = wrapper((_p1 + _p2) * ((_p3 + (P" " * _p4) + (P":" * _p5)) - #pos_typ_part) ^ 0, "file")
local link = pos("t_b") * file_part * P":" * pos_part * pos("t_e")
local file_pos_typ_part = link * P":" * typ_part

-- 4. program name and | parts
local program = loc.alpha * (S".-" + loc.alnum) ^ 1 * P":" * P" " ^ -1
local vbar = P" " ^ 1 * P"|" ^ -1

local p = CT(pos("b") * ((vbar + program) * file_pos_typ_part + file_pos_typ_part) * pos("e")) / function(t)
    t.link = { b = t.t_b, e = t.t_e }
    t.t_b = nil
    t.t_e = nil
    return t
end

return { multiline = 1, pattern = p }
