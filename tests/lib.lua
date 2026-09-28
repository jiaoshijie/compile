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

_M.cfg_pattern = function(matcher, case_filename)
    local case_file = fmt("%s/cases/%s", script_dir, case_filename)

    local lines = vim.fn.readfile(case_file)

    local res_lnum = tonumber(lines[1])
    local test_lines = vim.list_slice(lines, 2, res_lnum - 2)
    local res_lines = vim.list_slice(lines, res_lnum)

    eq(#test_lines, #res_lines)

    for i = 1,#test_lines do
        if res_lines[i] == "nil" then
            is_nil(matcher:match(test_lines[i]))
        elseif res_lines[i] == "print" then
            _M.print(vim.json.encode(matcher:match(test_lines[i])))
        elseif res_lines[i] == "number" then
            is_number(matcher:match(test_lines[i]))
        else
            eq(matcher:match(test_lines[i]), vim.json.decode(res_lines[i]))
        end
    end
end

_M.single_line_matcher = function(matcher_name, case_filename)
    local start_time = vim.uv.hrtime()
    _M.print(fmt("%s ...", matcher_name))
    local matcher = require("compile.matchers." .. matcher_name)
    local case_file = fmt("%s/cases/%s", script_dir, case_filename)

    local lines = vim.fn.readfile(case_file)

    local res_lnum = tonumber(lines[1])
    local test_lines = vim.list_slice(lines, 2, res_lnum - 2)
    local res_lines = vim.list_slice(lines, res_lnum)

    eq(#test_lines, #res_lines)
    eq(1, matcher.multiline)

    local i = 1

    while i <= #test_lines do
        if res_lines[i] == "nil" then
            is_nil(matcher.pattern:match(test_lines[i]))
        elseif res_lines[i] == "wrong" then
            _M.print(fmt("INFO: An unsupported format: `%s`", test_lines[i]))
        elseif res_lines[i] == "print" then
            _M.print(vim.json.encode(matcher.pattern:match(test_lines[i])))
        else
            eq(vim.json.decode(res_lines[i]), matcher.pattern:match(test_lines[i]))
        end
        i = i + 1
    end

    _M.print(fmt("%s DONE, duration: %.03fs",
        matcher_name, (vim.uv.hrtime() - start_time) / 1E9))
end

local get_matched_line_count = function(text, end_col)
    local count = 1

    local np = string.find(text, '\n')
    while np and end_col > np do
        count = count + 1
        np = string.find(text, '\n', np + 1)
    end

    return count
end

_M.multiline_matcher = function(matcher_name, case_filename)
    local start_time = vim.uv.hrtime()
    _M.print(fmt("%s ...", matcher_name))
    local matcher = require("compile.matchers." .. matcher_name)
    local case_file = fmt("%s/cases/%s", script_dir, case_filename)

    local lines = vim.fn.readfile(case_file)

    local res_lnum = tonumber(lines[1])
    local test_lines = vim.list_slice(lines, 2, res_lnum - 2)
    local res_lines = vim.list_slice(lines, res_lnum)

    eq(#test_lines, #res_lines)

    local i = 1
    local rest = matcher.multiline - 1

    while i <= #test_lines do
        if res_lines[i] == "" then
            unreachable()
        elseif res_lines[i] == "nil" then
            is_nil(matcher.pattern:match(test_lines[i]))
            i = i + 1
            goto continue
        elseif res_lines[i] == "number" then  -- only matched pattern1
            is_number(matcher.pattern:match(test_lines[i]))
            i = i + 1
            goto continue
        end
        is_number(matcher.pattern:match(test_lines[i]))

        local end_i = i + rest
        if end_i > #test_lines and matcher.opt_multiline then
            end_i = #test_lines
        end

        local text = table.concat(test_lines, '\n', i, end_i)
        local caps = matcher.pattern2:match(text)

        if res_lines[i] == "print" then
            _M.print(vim.json.encode(caps))
        else
            eq(vim.json.decode(res_lines[i]), caps)
        end

        local step = matcher.multiline

        if matcher.opt_multiline then
            step = get_matched_line_count(text, caps.e)
        end

        i = i + step
        ::continue::
    end

    _M.print(fmt("%s DONE, duration: %.03fs",
        matcher_name, (vim.uv.hrtime() - start_time) / 1E9))
end

return _M
