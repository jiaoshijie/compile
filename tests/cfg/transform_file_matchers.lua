local lib = require("tests.lib")
local fmt = string.format

local start_time = vim.uv.hrtime()

lib.print("transform_file_matchers ...")

------------------------------------------------------------------------------

local patterns = require("compile.config").transform_file_matchers
for i, pattern in ipairs(patterns) do
    lib.cfg_pattern(pattern, fmt("transform_file_matchers_%d.txt", i))
end

------------------------------------------------------------------------------

lib.print(fmt("transform_file_matchers DONE, duration: %.03fs", (vim.uv.hrtime() - start_time) / 1E9))
