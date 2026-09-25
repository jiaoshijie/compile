local lib = require("tests.lib")
local fmt = string.format

local start_time = vim.uv.hrtime()

lib.print("keyword_matchers ...")

------------------------------------------------------------------------------

local patterns = require("compile.config").keyword_matchers
for i, pattern in ipairs(patterns) do
    lib.cfg_pattern(pattern, fmt("keyword_matchers_%d.txt", i))
end

------------------------------------------------------------------------------

lib.print(fmt("keyword_matchers DONE, duration: %.03fs", (vim.uv.hrtime() - start_time) / 1E9))
