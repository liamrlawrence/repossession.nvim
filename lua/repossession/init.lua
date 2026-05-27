local M = {}


M.defaults = {
    git_session_file  = ".git/session.vim",
    git_shada_file    = ".git/session.shada",
    local_session_file = ".session.vim",
    global_shada_file = vim.fn.stdpath("data") .. "/repossession/global.shada",
}



function M.setup(opts)
    opts = vim.tbl_deep_extend("force", M.defaults, opts or {})

    local augroup = vim.api.nvim_create_augroup
    local session_group = augroup("repossession_nvim", { clear = true })

    vim.api.nvim_create_autocmd("VimEnter", {
        desc = "Initialize vim session",
        group = session_group,
        nested = true,
        callback = function()
            local session_file = nil
            local shada_file = opts.global_shada_file

            local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("\n", "")
            local in_git = vim.v.shell_error == 0
            local opened_dot = vim.fn.argc() == 1 and vim.fn.argv(0) == "."

            if in_git and opened_dot then
                -- 'nvim .' was run inside of a git project: git session, git shada
                session_file = git_root .. "/" .. opts.git_session_file
                shada_file = git_root .. "/" .. opts.git_shada_file
            elseif vim.fn.argc() == 0 then
                -- 'nvim' with no args: local session, global shada
                session_file = vim.fn.getcwd() .. "/" .. opts.local_session_file
                shada_file = opts.global_shada_file
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

                local save_timer = vim.uv.new_timer()

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

                        -- Timer may be nil if system resources are exhausted
                        if not save_timer then
                            vim.cmd("mksession! " .. vim.fn.fnameescape(session_file))
                            return
                        end

                        -- Debounce: wait 300ms before writing
                        save_timer:start(300, 0, vim.schedule_wrap(function()
                            vim.cmd("mksession! " .. vim.fn.fnameescape(session_file))
                        end))
                    end,
                })
            end
        end,
    })
end


return M

