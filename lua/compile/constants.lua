local fmt = string.format
local _M = {}

_M.default_name = "[compilation]"

------------------------------------------------------------------------------

---@enum CompileType
_M.CompileType = {
    COMP = 0,  -- compilation buffer
    NORMRO = 1,  -- normal file buffer readonly
    NORMRW = 2,  -- normal file buffer read and write
}

local _type2str = {
    [_M.CompileType.COMP] = "COMP",
    [_M.CompileType.NORMRO] = "NORMRO",
    [_M.CompileType.NORMRW] = "NORMRW",
}

_M.type2str = function(typ)
    local str = _type2str[typ]
    return str or "Unknown"
end

------------------------------------------------------------------------------

---@enum CompileSeverity
_M.Severity = {
    HINT = 0,
    INFO = 1,
    WARNING = 2,
    ERROR = 3,
}

local _Severity2str = {
    [_M.Severity.HINT] = "HINT",
    [_M.Severity.INFO] = "INFO",
    [_M.Severity.WARNING] = "WARNING",
    [_M.Severity.ERROR] = "ERROR",
}

local _str2Severity = {
    ["HINT"] = _M.Severity.HINT,
    ["INFO"] = _M.Severity.INFO,
    ["WARNING"] = _M.Severity.WARNING,
    ["ERROR"] = _M.Severity.ERROR,
}

local _Severity2hl = {
    [_M.Severity.HINT] = "CompileLuaHint",
    [_M.Severity.INFO] = "CompileLuaInfo",
    [_M.Severity.WARNING] = "CompileLuaWarning",
    [_M.Severity.ERROR] = "CompileLuaError",
}

--- @param level CompileSeverity | integer
--- @return string
_M.get_hl_by_severity = function(level)
    level = level or _M.Severity.ERROR
    return _Severity2hl[level] or "CompileLuaError"
end

--- @param level CompileSeverity | integer
--- @return CompileSeverity
_M.get_valid_severity = function(level)
    if type(level) == "number"
        and level >= _M.Severity.HINT
        and level <= _M.Severity.ERROR then
        return level
    end

    return _M.Severity.ERROR
end

--- @param level CompileSeverity | integer
_M.get_str_by_severity = function(level)
    level = level or _M.Severity.ERROR
    return _Severity2str[level] or "ERROR"
end

--- @return CompileSeverity?
_M.get_severity_by_str = function(str)
    return _str2Severity[str]
end

_M.get_severity_strs = function()
    return vim.tbl_keys(_str2Severity)
end

------------------------------------------------------------------------------

-- `man 3 strsignal`
local _signal_msg = {
    [vim.uv.constants.SIGHUP]    = "Hangup",
    [vim.uv.constants.SIGINT]    = "Interrupt",
    [vim.uv.constants.SIGQUIT]   = "Quit",
    [vim.uv.constants.SIGILL]    = "Illegal instruction",
    [vim.uv.constants.SIGTRAP]   = "Trace/breakpoint trap",
    [vim.uv.constants.SIGABRT]   = "Aborted",
    [vim.uv.constants.SIGBUS]    = "Bus error",
    [vim.uv.constants.SIGFPE]    = "Floating point exception",
    [vim.uv.constants.SIGKILL]   = "Killed",
    [vim.uv.constants.SIGUSR1]   = "User defined signal 1",
    [vim.uv.constants.SIGSEGV]   = "Segmentation fault",
    [vim.uv.constants.SIGUSR2]   = "User defined signal 2",
    [vim.uv.constants.SIGPIPE]   = "Broken pipe",
    [vim.uv.constants.SIGALRM]   = "Alarm clock",
    [vim.uv.constants.SIGTERM]   = "Terminated",
    [vim.uv.constants.SIGSTKFLT] = "Stack fault",
    [vim.uv.constants.SIGCHLD]   = "Child exited",
    [vim.uv.constants.SIGCONT]   = "Continued",
    [vim.uv.constants.SIGSTOP]   = "Stopped by signal",
    [vim.uv.constants.SIGTSTP]   = "Stopped",
    [vim.uv.constants.SIGTTIN]   = "Stopped by tty input",
    [vim.uv.constants.SIGTTOU]   = "Stopped by tty output",
    [vim.uv.constants.SIGURG]    = "Urgent I/O condition",
    [vim.uv.constants.SIGXCPU]   = "CPU time limit exceeded",
    [vim.uv.constants.SIGXFSZ]   = "File size limit exceeded",
    [vim.uv.constants.SIGVTALRM] = "Virtual timer expired",
    [vim.uv.constants.SIGPROF]   = "Profiling timer expired",
    [vim.uv.constants.SIGWINCH]  = "Window changed",
    [vim.uv.constants.SIGIO]     = "I/O possible",
    [vim.uv.constants.SIGPWR]    = "Power failure",
    [vim.uv.constants.SIGSYS]    = "Bad system call",
}

_M.get_signal_str = function(sig_code)
    return _signal_msg[sig_code]
end

--- @param ret_code integer
--- @return string
_M.get_err_msg = function(ret_code)
    if ret_code > 128 then
        local sig_code = ret_code - 128
        local msg = _signal_msg[sig_code]
        if msg then
            return fmt("%s(%d)", msg, sig_code)
        end
    end

    return fmt("exited abnormally(%d)", ret_code)
end

------------------------------------------------------------------------------

_M.ui = {
    cache_size = 500,  -- 500 1000 2000
    cache_flush_interval = 100, -- unit: ms
}

------------------------------------------------------------------------------

return _M
