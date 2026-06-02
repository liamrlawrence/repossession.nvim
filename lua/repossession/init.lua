local M = {}
local commands = require("repossession.commands")
local session_group = vim.api.nvim_create_augroup("repossession_nvim", { clear = true })
local active_session_file = nil


M.defaults = {
    local_sentinel    = "=",
    git_sentinel      = ",",
    git_session_file  = ".git/session.vim",
    git_shada_file    = ".git/session.shada",
    global_shada_file = vim.fn.stdpath("data") .. "/repossession/global.shada",
    tidy_dir          = vim.fn.stdpath("data") .. "/repossession",
    tidy_sessions     = false,
}



local function register_save_autocmd(session_file)
    active_session_file = session_file

    vim.api.nvim_clear_autocmds({ group = session_group })
    vim.api.nvim_create_autocmd({
        "BufAdd", "BufDelete", "BufEnter",
        "WinNew", "WinClosed",
        "TabNew", "TabClosed",
        "VimLeavePre",
    }, {
        desc = "Save vim session",
        group = session_group,
        callback = function(ev)
            -- Ignore floating windows (hover docs, telescope, etc.)
            if ev.event ~= "VimLeavePre" then
                local win = vim.api.nvim_get_current_win()
                if vim.api.nvim_win_get_config(win).relative ~= "" then return end
            end

            vim.cmd("mksession! " .. vim.fn.fnameescape(session_file))
        end,
    })
end


function M.setup(opts)
    opts = vim.tbl_deep_extend("force", M.defaults, opts or {})

    -- Guards
    if opts.git_sentinel == opts.local_sentinel then
        vim.notify(
            "repossession.nvim: git_sentinel and local_sentinel must be different",
            vim.log.levels.ERROR
        )
        return
    end

    -- Commands
    vim.api.nvim_create_user_command("Repossession", function()
        commands.repossession(opts, register_save_autocmd, active_session_file)
    end, { desc = "Browse and load available sessions for the current context" })

    -- Initialize
    vim.api.nvim_create_autocmd("VimEnter", {
        desc = "Initialize vim session",
        group = session_group,
        nested = true,
        callback = function()
            local session_file = nil
            local shada_file = opts.global_shada_file
            local sentinel_arg = nil

            local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("\n", "")
            local in_git = vim.v.shell_error == 0

            local arg0 = vim.fn.argc() == 1 and (vim.fn.argv(0) --[[@as string]]) or nil
            local git_sentinel_arg = arg0 == opts.git_sentinel
            local local_sentinel_arg = arg0 ~= nil
                and vim.startswith(arg0, opts.local_sentinel)
                and vim.fn.filereadable(arg0) == 0
                and vim.fn.isdirectory(arg0) == 0

            if in_git and git_sentinel_arg then
                -- 'nvim ,' was run inside of a git project: git session, git shada
                session_file = git_root .. "/" .. opts.git_session_file
                shada_file   = git_root .. "/" .. opts.git_shada_file
                sentinel_arg = arg0
            elseif local_sentinel_arg then
                -- 'nvim =' was run: local session, local shada
                local session_name = assert(arg0):sub(#opts.local_sentinel + 1)
                local suffix       = session_name == "" and "" or "_" .. session_name

                if opts.tidy_sessions then
                    -- store in a hashed directory under tidy_dir
                    local cwd = vim.fn.getcwd()
                    local dir = opts.tidy_dir .. "/" .. vim.fn.sha256(cwd):sub(1, 8)
                    vim.fn.mkdir(dir, "p")

                    local sessionpath_file = dir .. "/SESSIONPATH"
                    if vim.fn.filereadable(sessionpath_file) == 0 then
                        local f = io.open(sessionpath_file, "w")
                        if f then
                            f:write(cwd .. "\n")
                            f:close()
                        end
                    end

                    session_file = dir .. "/session" .. suffix .. ".vim"
                    shada_file   = dir .. "/session" .. suffix .. ".shada"
                else
                    -- store in cwd with a dot prefix
                    local dir = vim.fn.getcwd()
                    session_file = dir .. "/.session" .. suffix .. ".vim"
                    shada_file   = dir .. "/.session" .. suffix .. ".shada"
                end

                sentinel_arg = arg0
            else
                -- no session, global shada
            end

            -- Load shada
            vim.opt.shadafile = shada_file
            if vim.fn.filereadable(shada_file) == 1 then
                vim.cmd("rshada!")
            end

            -- Load session
            if session_file then
                if vim.fn.filereadable(session_file) == 1 then
                    vim.cmd("source " .. vim.fn.fnameescape(session_file))
                end

                -- Wipe sentinel buffer after session has loaded
                if sentinel_arg then
                    local sentinel_buf = vim.fn.bufnr(sentinel_arg)
                    if sentinel_buf ~= -1 then
                        vim.api.nvim_buf_delete(sentinel_buf, { force = true })
                    end
                end

                register_save_autocmd(session_file)
            end
        end,
    })
end


return M

