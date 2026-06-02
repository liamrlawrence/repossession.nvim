local M = {}



function M.repossession(opts, register_save_autocmd)
    local sessions = {}

    -- Check for git session
    local git_root = vim.fn.system("git rev-parse --show-toplevel"):gsub("\n", "")
    local in_git = vim.v.shell_error == 0
    if in_git then
        local git_session = git_root .. "/" .. opts.git_session_file
        if vim.fn.filereadable(git_session) == 1 then
            table.insert(sessions, {
                label        = "[git]   " .. git_root,
                display      = "[git] " .. git_root,
                session_file = git_session,
            })
        end
    end

    -- Find local sessions
    local cwd = vim.fn.getcwd()
    local scan_dir = opts.tidy_sessions and opts.tidy_dir .. "/" .. vim.fn.sha256(cwd):sub(1, 8) or cwd
    local file_pattern = opts.tidy_sessions and "^session.*%.vim$" or "^%.session.*%.vim$"
    local name_capture = opts.tidy_sessions and "^session_(.+)%.vim$" or "^%.session_(.+)%.vim$"

    local handle = vim.uv.fs_scandir(scan_dir)
    if handle then
        while true do
            local fname, ftype = vim.uv.fs_scandir_next(handle)
            if not fname then break end
            if ftype == "file" and fname:match(file_pattern) then
                local session_name = fname:match(name_capture) or "(default)"
                local prefix_label = in_git and "[local] " or ""
                table.insert(sessions, {
                    label        = prefix_label .. session_name,
                    display      = session_name,
                    session_file = scan_dir .. "/" .. fname,
                })
            end
        end
    end

    if #sessions == 0 then
        vim.notify("repossession.nvim: no sessions found", vim.log.levels.INFO)
        return
    end


    -- Build floating window
    table.sort(sessions, function(a, b) return a.label < b.label end)   -- Sort alphabetically by label

    local lines = {}
    for i, s in ipairs(sessions) do
        table.insert(lines, string.format(" %d  %s", i, s.label))
    end

    local width = math.min(80, math.max(30, (function()
        local max = 0
        for _, l in ipairs(lines) do max = math.max(max, #l) end
        return max + 2
    end)()))
    local height = #lines
    local row    = math.floor((vim.o.lines - height) / 2)
    local col    = math.floor((vim.o.columns - width) / 2)

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    local win = vim.api.nvim_open_win(buf, true, {
        relative  = "editor",
        width     = width,
        height    = height,
        row       = row,
        col       = col,
        style     = "minimal",
        border    = "rounded",
        title     = " Repossession ",
        title_pos = "center",
    })
    vim.wo[win].cursorline = true

    -- Functions
    local function load_session(idx)
        local s = sessions[idx]
        if s then
            vim.api.nvim_win_close(win, true)

            -- Load shada
            local shada_file = s.session_file:gsub("%.vim$", ".shada")
            if vim.fn.filereadable(shada_file) == 1 then
                vim.opt.shadafile = shada_file
                vim.cmd("rshada!")
            end

            -- Load session
            vim.cmd("source " .. vim.fn.fnameescape(s.session_file))
            vim.notify("repossession.nvim: loaded session | " .. s.display, vim.log.levels.INFO)

            -- Re-register save autocmd with the new session file
            register_save_autocmd(s.session_file)
        end
    end

    -- Keymaps
    vim.keymap.set("n", "q",     function() vim.api.nvim_win_close(win, true)                 end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true)                 end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<CR>",  function() load_session(vim.api.nvim_win_get_cursor(win)[1]) end, { buffer = buf, nowait = true })
end


return M

