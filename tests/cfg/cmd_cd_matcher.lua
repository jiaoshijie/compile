local lib = require("tests.lib")
local fmt = string.format

local start_time = vim.uv.hrtime()

lib.print("cmd_cd_matcher ...")

------------------------------------------------------------------------------

local p = require("compile.config").cmd_cd_matcher
lib.cfg_pattern(p, "cmd_cd_matcher.txt")

------------------------------------------------------------------------------

lib.print(fmt("cmd_cd_matcher DONE, duration: %.03fs", (vim.uv.hrtime() - start_time) / 1E9))

