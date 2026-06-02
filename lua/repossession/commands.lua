local M = {}
local picker_win_id = nil



local function scan_sessions(cwd, opts)
    local sessions = {}

    -- Check for git session
    local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " rev-parse --show-toplevel")[1] or nil
    local in_git = vim.v.shell_error == 0
    if in_git then
        local git_session = git_root .. "/" .. opts.git_session_file
        if vim.fn.filereadable(git_session) == 1 then
            table.insert(sessions, {
                label        = "[git]   " .. git_root,
                display      = "git:" .. git_root,
                session_file = git_session,
                git          = true,
                git_root     = git_root,
            })
        end
    end

    -- Find local sessions
    local scan_dir = opts.tidy_sessions and opts.tidy_dir .. "/" .. vim.fn.sha256(cwd):sub(1, 8) or cwd
    local file_pattern = opts.tidy_sessions and "^session.*%.vim$"    or "^%.session.*%.vim$"
    local name_capture = opts.tidy_sessions and "^session_(.+)%.vim$" or "^%.session_(.+)%.vim$"

    local handle = vim.uv.fs_scandir(scan_dir)
    if handle then
        while true do
            local fname, ftype = vim.uv.fs_scandir_next(handle)
            if not fname then break end
            if ftype == "file" and fname:match(file_pattern) then
                local session_name = fname:match(name_capture)
                local prefix_label = in_git and "[local] " or ""
                table.insert(sessions, {
                    label        = prefix_label .. (session_name or "(default)"),
                    display      = session_name or "(default)",
                    session_file = scan_dir .. "/" .. fname,
                    git          = false,
                })
            end
        end
    end

    table.sort(sessions, function(a, b) return a.label < b.label end)
    return sessions, scan_dir
end


local function render_picker(sessions, scan_dir, opts, cwd, activate_session, activate_shada, get_active_session_file)
    local active_session_file = get_active_session_file()
    if picker_win_id and vim.api.nvim_win_is_valid(picker_win_id) then
        vim.api.nvim_set_current_win(picker_win_id)
        return
    end

    if #sessions == 0 then
        vim.notify("repossession.nvim: no sessions found", vim.log.levels.INFO)
        return
    end

    local lines = {}
    local active_idx = 1
    for i, s in ipairs(sessions) do
        local marker = s.session_file == active_session_file and "~ " or "  "
        table.insert(lines, string.format(" %d  %s%s", i, marker, s.display))
        if s.session_file == active_session_file then
            active_idx = i
        end
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
    picker_win_id = win
    vim.api.nvim_win_set_cursor(win, { active_idx, 0 })

    vim.api.nvim_create_autocmd("WinClosed", {
        pattern  = tostring(win),
        once     = true,
        callback = function()
            picker_win_id = nil
        end,
    })

    local function rerender()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        local new_sessions, new_scan_dir = scan_sessions(cwd, opts)
        render_picker(new_sessions, new_scan_dir, opts, cwd, activate_session, activate_shada, get_active_session_file)
    end


    -- Picker functions
    local function load_session(idx)
        local s = sessions[idx]
        if not s then return end

        -- Check for unsaved buffers
        local unsaved = {}
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(b)
                and vim.bo[b].modified
                and vim.api.nvim_buf_get_name(b) ~= "" then
                table.insert(unsaved, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(b), ":~:."))
            end
        end
        if #unsaved > 0 then
            vim.notify(
                "repossession.nvim: unsaved changes in [" .. table.concat(unsaved, ", ") .. "]",
                vim.log.levels.WARN
            )
            return
        end
        vim.api.nvim_win_close(win, true)

        -- Load shada
        local shada_file = s.session_file:gsub("%.vim$", ".shada")
        activate_shada(shada_file)

        -- Load session
        activate_session(s.session_file, s.git_root)
        vim.notify("repossession.nvim: loaded session [" .. s.display .. "]", vim.log.levels.INFO)
    end


    local function create_session()
        vim.api.nvim_win_close(win, true)
        local new_name = vim.fn.input("New session name: "):gsub("\n", "")
        local new_session_file = new_name == ""
            and (opts.tidy_sessions and scan_dir .. "/session.vim"                        or scan_dir .. "/.session.vim")
            or  (opts.tidy_sessions and scan_dir .. "/session_" .. new_name .. ".vim"     or scan_dir .. "/.session_" .. new_name .. ".vim")

        if vim.fn.filereadable(new_session_file) == 1 then
            local target = new_name == "" and "default" or new_name
            vim.notify("repossession.nvim: session [" .. target .. "] already exists", vim.log.levels.WARN)
            rerender()
            return
        end

        vim.cmd("mksession! " .. vim.fn.fnameescape(new_session_file))
        local display_name = new_name == "" and "default" or new_name
        vim.notify("repossession.nvim: created session [" .. display_name .. "]", vim.log.levels.INFO)
        rerender()
    end


    local function rename_session(idx)
        local s = sessions[idx]
        if not s or s.git then
            vim.notify("repossession.nvim: git sessions cannot be renamed", vim.log.levels.WARN)
            return
        end

        vim.api.nvim_win_close(win, true)
        local new_name = vim.fn.input("Rename session to: "):gsub("\n", "")
        local new_session_file = new_name == ""
            and (opts.tidy_sessions and scan_dir .. "/session.vim"                        or scan_dir .. "/.session.vim")
            or  (opts.tidy_sessions and scan_dir .. "/session_" .. new_name .. ".vim"     or scan_dir .. "/.session_" .. new_name .. ".vim")

        local new_shada_file = new_session_file:gsub("%.vim$", ".shada")
        local old_shada_file = s.session_file:gsub("%.vim$", ".shada")
        if vim.fn.filereadable(new_session_file) == 1 then
            local target = new_name == "" and "default" or new_name
            vim.notify("repossession.nvim: session [" .. target .. "] already exists", vim.log.levels.WARN)
            rerender()
            return
        end

        local ok, err = os.rename(s.session_file, new_session_file)
        if not ok then
            vim.notify("repossession.nvim: failed to rename session file: " .. err, vim.log.levels.ERROR)
            rerender()
            return
        end

        if vim.fn.filereadable(old_shada_file) == 1 then
            ok, err = os.rename(old_shada_file, new_shada_file)
            if not ok then
                vim.notify("repossession.nvim: failed to rename shada file: " .. err, vim.log.levels.ERROR)
                rerender()
                return
            end
        end

        local display_name = new_name == "" and "default" or new_name
        if s.session_file == active_session_file then
            activate_shada(new_shada_file)
            activate_session(new_session_file)
            vim.notify("repossession.nvim: renamed current session to [" .. display_name .. "]", vim.log.levels.INFO)
        else
            vim.notify("repossession.nvim: renamed session to [" .. display_name .. "]", vim.log.levels.INFO)
        end
        rerender()
    end


    local function delete_session(idx)
        local s = sessions[idx]
        if not s or s.git then
            vim.notify("repossession.nvim: git sessions cannot be deleted", vim.log.levels.WARN)
            return
        end

        if s.session_file == active_session_file then
            vim.notify("repossession.nvim: cannot delete the active session", vim.log.levels.WARN)
            return
        end

        vim.api.nvim_win_close(win, true)
        local confirm = vim.fn.input("Delete session [" .. s.display .. "]? (y/n): ")
        if confirm ~= "y" then
            vim.notify("repossession.nvim: delete cancelled", vim.log.levels.INFO)
            rerender()
            return
        end

        local ok, err = os.remove(s.session_file)
        if not ok then
            vim.notify("repossession.nvim: failed to delete session file: " .. err, vim.log.levels.ERROR)
            rerender()
            return
        end

        local shada_file = s.session_file:gsub("%.vim$", ".shada")
        if vim.fn.filereadable(shada_file) == 1 then
            ok, err = os.remove(shada_file)
            if not ok then
                vim.notify("repossession.nvim: failed to delete shada file: " .. err, vim.log.levels.ERROR)
                rerender()
                return
            end
        end

        vim.notify("repossession.nvim: deleted session [" .. s.display .. "]", vim.log.levels.INFO)
        rerender()
    end


    -- Keymaps
    vim.keymap.set("n", "q",     function() vim.api.nvim_win_close(win, true)                   end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true)                   end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<CR>",  function() load_session(vim.api.nvim_win_get_cursor(win)[1])   end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "c",     function() create_session()                                    end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "r",     function() rename_session(vim.api.nvim_win_get_cursor(win)[1]) end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "d",     function() delete_session(vim.api.nvim_win_get_cursor(win)[1]) end, { buffer = buf, nowait = true })
end


function M.repossession(opts, cwd, activate_session, activate_shada, get_active_session_file)
    local sessions, scan_dir = scan_sessions(cwd, opts)
    render_picker(sessions, scan_dir, opts, cwd, activate_session, activate_shada, get_active_session_file)
end


return M

