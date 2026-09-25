local lib = require("tests.lib")
local fmt = string.format

local start_time = vim.uv.hrtime()

lib.print("directory_matcher ...")

------------------------------------------------------------------------------

local p = require("compile.config").directory_matcher
lib.cfg_pattern(p, "directory_matcher.txt")

------------------------------------------------------------------------------

lib.print(fmt("directory_matcher DONE, duration: %.03fs", (vim.uv.hrtime() - start_time) / 1E9))
