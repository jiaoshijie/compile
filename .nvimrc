lua<<EOF
local kit = require("kit")
local found, ffmk = pcall(require, "ffmk")

if not found then
    return
end

local files_cmd = {
    ignore_patterns = {
        "tests/"
    }
}

kit.v.ffmk_ctrlp_func = function()
    ffmk.files({
        ui = { preview = false },
        cmd = {
            prompt = "compile.lua❯ ",
            cmd = kit.find_files_cmd(files_cmd),
            hidden = true,
            no_ignore = false,
            follow = false,
        }
    })
end
EOF
