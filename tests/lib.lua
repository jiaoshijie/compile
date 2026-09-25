local fmt = string.format

local eq = function(expected, actual)
  if not vim.deep_equal(expected, actual) then
    error(fmt("expected: %s\nactual:   %s", vim.inspect(expected),
            vim.inspect(actual)), 2)
  end
end

local is_nil = function(value)
  if value ~= nil then
    error(fmt("expected nil, got %s", vim.inspect(value)), 2)
  end
end

local is_number = function(value)
  if type(value) ~= "number" then
    error(fmt("expected number, got %s", vim.inspect(value)), 2)
  end
end

local unreachable = function()
    error("unreachable", 2)
end


local _M = {}
local script_dir = debug.getinfo(1, "S").source:gsub("^@", ""):match("(.*/)")

_M.print = function(msg)
    io.stdout:write(msg, "\n")
    io.stdout:flush()
end

_M.cfg_pattern = function(pattern, case_filename)
    local case_file = fmt("%s/cases/%s", script_dir, case_filename)

    local lines = vim.fn.readfile(case_file)

    local res_lnum = tonumber(lines[1])
    local test_lines = vim.list_slice(lines, 2, res_lnum - 2)
    local res_lines = vim.list_slice(lines, res_lnum)

    eq(#test_lines, #res_lines)

    for i = 1,#test_lines do
        if res_lines[i] == "nil" then
            is_nil(pattern:match(test_lines[i]))
        elseif res_lines[i] == "print" then
            _M.print(vim.json.encode(pattern:match(test_lines[i])))
        elseif res_lines[i] == "number" then
            is_number(pattern:match(test_lines[i]))
        else
            eq(pattern:match(test_lines[i]), vim.json.decode(res_lines[i]))
        end
    end
end

_M.single_line_parser = function(parser_name, case_filename)
    local start_time = vim.uv.hrtime()
    _M.print(fmt("%s ...", parser_name))
    local parser = require("compile.matchers." .. parser_name)
    local case_file = fmt("%s/cases/%s", script_dir, case_filename)

    local lines = vim.fn.readfile(case_file)

    local res_lnum = tonumber(lines[1])
    local test_lines = vim.list_slice(lines, 2, res_lnum - 2)
    local res_lines = vim.list_slice(lines, res_lnum)

    eq(#test_lines, #res_lines)
    eq(parser.multiline, 1)

    local i = 1

    while i <= #test_lines do
        if res_lines[i] == "nil" then
            is_nil(parser.pattern:match(test_lines[i]))
        elseif res_lines[i] == "wrong" then
            _M.print(fmt("INFO: An unsupported format: `%s`", test_lines[i]))
        elseif res_lines[i] == "print" then
            _M.print(vim.json.encode(parser.pattern:match(test_lines[i])))
        else
            eq(vim.json.decode(res_lines[i]), parser.pattern:match(test_lines[i]))
        end
        i = i + 1
    end

    _M.print(fmt("%s DONE, duration: %.03fs",
        parser_name, (vim.uv.hrtime() - start_time) / 1E9))
end

_M.multiline_parser = function(parser_name, case_filename)
    local start_time = vim.uv.hrtime()
    _M.print(fmt("%s ...", parser_name))
    local parser = require("compile.matchers." .. parser_name)
    local case_file = fmt("%s/cases/%s", script_dir, case_filename)

    local lines = vim.fn.readfile(case_file)

    local res_lnum = tonumber(lines[1])
    local test_lines = vim.list_slice(lines, 2, res_lnum - 2)
    local res_lines = vim.list_slice(lines, res_lnum)

    eq(#test_lines, #res_lines)

    local i = 1
    local rest = parser.multiline - 1

    while i <= #test_lines do
        if res_lines[i] == "" then
            unreachable()
        elseif res_lines[i] == "nil" then
            is_nil(parser.pattern:match(test_lines[i]))
            i = i + 1
            goto continue
        elseif res_lines[i] == "number" then
            is_number(parser.pattern:match(test_lines[i]))
            i = i + 1
            goto continue
        end

        is_number(parser.pattern:match(test_lines[i]))

        if res_lines[i] == "print" then
            _M.print(vim.json.encode(
                parser.pattern2:match(table.concat(test_lines, '\n', i, i + rest))))
        else
            eq(vim.json.decode(res_lines[i]),
                parser.pattern2:match(table.concat(test_lines, '\n', i, i + rest)))
        end

        i = i + parser.multiline
        ::continue::
    end

    _M.print(fmt("%s DONE, duration: %.03fs",
        parser_name, (vim.uv.hrtime() - start_time) / 1E9))
end

return _M
