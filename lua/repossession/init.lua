local M = {}
local cwd = vim.fn.getcwd()
local repossession_group = vim.api.nvim_create_augroup("repossession_nvim", { clear = true })
local active_session_file = nil
local active_git_root = nil
local last_session_file = nil
local last_git_root = nil
local picker_win_id = nil


M.defaults = {
    local_sentinel    = "=",
    git_sentinel      = ",",
    git_session_file  = ".git/session.vim",
    git_shada_file    = ".git/session.shada",
    global_shada_file = vim.fn.stdpath("data") .. "/repossession/global.shada",
    tidy_dir          = vim.fn.stdpath("data") .. "/repossession",
    tidy_sessions     = true,
    ignore_filetypes  = {},
}

local opts = M.defaults


local function get_session_name(session_file)
    local git_dir = session_file:match("(.-)/%.git/.*")
    if git_dir then
        return "git:" .. git_dir
    end

    local name = session_file:match("session_(.-)%.vim$")
              or session_file:match("%.session_(.-)%.vim$")

    if not name or name == "" then
        return "(default)"
    end

    return name
end


local function ensure_tidy_dir(dir)
    local sessionpath_file = dir .. "/SESSIONPATH"
    vim.fn.mkdir(dir, "p")
    if vim.fn.filereadable(sessionpath_file) == 0 then
        local f = io.open(sessionpath_file, "w")
        if f then
            f:write(cwd .. "\n")
            f:close()
        end
    end
end


local function safe_mksession(session_file)
    local tmp = session_file .. ".tmp"
    local ok, err = pcall(function() vim.cmd("mksession! " .. vim.fn.fnameescape(tmp)) end)
    if not ok then
        local log = io.open(vim.fn.stdpath("data") .. "/repossession/error.log", "a")
        if log then
            log:write(os.date() .. " failed to save session: " .. err .. "\n")
            log:close()
        end
        os.remove(tmp)
        return
    end
    os.rename(tmp, session_file)
end


local function drop_ignored_buffers()
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.tbl_contains(opts.ignore_filetypes, vim.bo[b].filetype) then
            pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
    end
end


local function activate_shada(shada_file)
    vim.opt.shadafile = shada_file
    if vim.fn.filereadable(shada_file) == 1 then
        vim.cmd("rshada!")
    end
end


local function activate_session(session_file, git_root, args)
    args = args or {}
    local track_history = args.track_history
    local flush_path = args.flush_path or active_session_file

    vim.api.nvim_clear_autocmds({ group = repossession_group })

    if active_session_file then
        vim.api.nvim_exec_autocmds("User", {
            pattern = "RepossessionSwitchPre",
            data = {
                old_session = active_session_file,
                new_session = session_file,
            },
        })

        -- Drop ignored-filetype buffers so they are not written into the
        -- outgoing session, then do a deterministic final save after Pre
        -- handlers have cleaned up ephemeral UI.
        drop_ignored_buffers()
        safe_mksession(flush_path)
    end

    if track_history ~= false then
        last_session_file = active_session_file
        last_git_root = active_git_root
    end
    active_session_file = session_file
    active_git_root = git_root

    vim.api.nvim_create_autocmd({
        "BufAdd", "BufDelete", "BufEnter",
        "WinNew", "WinClosed",
        "TabNew", "TabClosed",
        "VimLeavePre",
    }, {
        desc = "Save vim session",
        group = repossession_group,
        callback = function(ev)
            -- On exit, fire the switch-pre hook so autocmds can
            -- clean up ephemeral UI before the final save
            if ev.event == "VimLeavePre" then
                if active_session_file then
                    vim.api.nvim_exec_autocmds("User", {
                        pattern = "RepossessionSwitchPre",
                        data = {
                            old_session = active_session_file,
                            new_session = nil,
                        },
                    })
                end
                drop_ignored_buffers()
                safe_mksession(session_file)
                return
            end

            -- Ignore floating windows (hover docs, telescope, etc.)
            local win = vim.api.nvim_get_current_win()
            if vim.api.nvim_win_get_config(win).relative ~= "" then return end

            safe_mksession(session_file)
        end,
    })

    if vim.fn.filereadable(session_file) == 1 then
        vim.cmd("source " .. vim.fn.fnameescape(session_file))
    end

    if git_root then
        vim.fn.chdir(git_root)
    else
        vim.fn.chdir(cwd)
    end

    vim.api.nvim_exec_autocmds("User", {
        pattern = "RepossessionSwitchPost",
        data = {
            session_file = session_file,
            session_name = get_session_name(session_file),
            git_root     = git_root,
        },
    })
end


local function scan_sessions()
    local sessions = {}

    -- Check for git session
    local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " rev-parse --show-toplevel")[1] or nil
    local in_git = vim.v.shell_error == 0
    if in_git then
        local git_session = git_root .. "/" .. opts.git_session_file
        if vim.fn.filereadable(git_session) == 1 then
            table.insert(sessions, {
                session_file = git_session,
                git          = true,
                git_root     = git_root,
            })
        end
    end

    -- Find local sessions
    local scan_dir = opts.tidy_sessions and opts.tidy_dir .. "/" .. vim.fn.sha256(cwd):sub(1, 8) or cwd
    local file_pattern = opts.tidy_sessions and "^session.*%.vim$"    or "^%.session.*%.vim$"

    local handle = vim.uv.fs_scandir(scan_dir)
    if handle then
        while true do
            local fname, ftype = vim.uv.fs_scandir_next(handle)
            if not fname then break end
            if ftype == "file" and fname:match(file_pattern) then
                table.insert(sessions, {
                    session_file = scan_dir .. "/" .. fname,
                    git          = false,
                    git_root     = nil,
                })
            end
        end
    end

    table.sort(sessions, function(a, b)
        if a.git ~= b.git then
            return a.git
        end
        return get_session_name(a.session_file) < get_session_name(b.session_file)
    end)

    return sessions, scan_dir
end


local function open_picker(sessions)
    local lines = {}
    local active_idx = 1
    for i, s in ipairs(sessions) do
        local marker = s.session_file == active_session_file and "~ " or "  "
        local session_name = get_session_name(s.session_file)
        table.insert(lines, string.format(" %d  %s%s", i, marker, session_name))
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
        callback = function() picker_win_id = nil end,
    })

    return buf, win
end


local function get_unsaved_buffers()
    local unsaved = {}
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified then
            local name = vim.api.nvim_buf_get_name(b)
            table.insert(unsaved, name ~= "" and vim.fn.fnamemodify(name, ":~:.") or "[No Name]")
        end
    end
    return unsaved
end


local function repossession(opts_cmd)
    local args = opts_cmd and opts_cmd.fargs or {}

    -- Scan for sessions
    local sessions, scan_dir = scan_sessions()
    if picker_win_id and vim.api.nvim_win_is_valid(picker_win_id) then
        vim.api.nvim_set_current_win(picker_win_id)
        return
    end

    if #sessions == 0 then
        vim.notify("No sessions found", vim.log.levels.INFO, { title = "repossession.nvim" })
        return
    end

    -- Subcommand: last
    if args[1] == "last" then
        if not last_session_file then
            vim.notify("No previous session", vim.log.levels.WARN, { title = "repossession.nvim" })
            return
        end

        local unsaved = get_unsaved_buffers()
        if #unsaved > 0 then
            vim.notify("Unsaved changes in [" .. table.concat(unsaved, ", ") .. "]", vim.log.levels.WARN, { title = "repossession.nvim" })
            return
        end

        local last_session_name = get_session_name(last_session_file)
        local last_shada_file = last_session_file:gsub("%.vim$", ".shada")
        activate_shada(last_shada_file)
        activate_session(last_session_file, last_git_root)
        vim.notify("Toggled session [" .. last_session_name .. "]", vim.log.levels.INFO, { title = "repossession.nvim" })
        return
    end


    -- Session picker
    local buf, win = open_picker(sessions)


    local function rerender()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
        repossession()
    end


    local function input(prompt)
        -- Input that returns nil on <Esc>
        local CANCELLED = "\0"
        local ok, result = pcall(vim.fn.input, { prompt = prompt, cancelreturn = CANCELLED })
        if not ok or result == CANCELLED then return nil end
        return result:gsub("\n", "")
    end


    local function get_new_session_path(new_name)
        return new_name == ""
            and (opts.tidy_sessions and scan_dir .. "/session.vim"                    or scan_dir .. "/.session.vim")
            or  (opts.tidy_sessions and scan_dir .. "/session_" .. new_name .. ".vim" or scan_dir .. "/.session_" .. new_name .. ".vim")
    end


    local function load_session(idx)
        local s = sessions[idx]
        if not s then return end

        local unsaved = get_unsaved_buffers()
        if #unsaved > 0 then
            vim.notify("Unsaved changes in [" .. table.concat(unsaved, ", ") .. "]", vim.log.levels.WARN, { title = "repossession.nvim" })
            return
        end

        vim.api.nvim_win_close(win, true)

        local session_name = get_session_name(s.session_file)
        local shada_file = s.session_file:gsub("%.vim$", ".shada")
        activate_shada(shada_file)
        activate_session(s.session_file, s.git_root)

        vim.notify("Loaded session [" .. session_name .. "]", vim.log.levels.INFO, { title = "repossession.nvim" })
    end


    local function new_session()
        local new_name = input("New session name: ")
        if new_name == nil then
            vim.notify("New session cancelled", vim.log.levels.INFO, { title = "repossession.nvim" })
            return
        end

        local new_session_file = get_new_session_path(new_name)
        local session_name = get_session_name(new_session_file)
        if vim.fn.filereadable(new_session_file) == 1 then
            vim.notify("Session [" .. session_name .. "] already exists", vim.log.levels.WARN, { title = "repossession.nvim" })
            return
        end

        vim.api.nvim_win_close(win, true)

        if opts.tidy_sessions then
            local dir = vim.fn.fnamemodify(new_session_file, ":h")
            ensure_tidy_dir(dir)
        end

        local new_shada_file = new_session_file:gsub("%.vim$", ".shada")
        activate_shada(new_shada_file)
        activate_session(new_session_file, nil)

        -- Wipe all buffers to start fresh
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_valid(b) then
                pcall(vim.api.nvim_buf_delete, b, { force = true })
            end
        end

        vim.notify("Created new session [" .. session_name .. "]", vim.log.levels.INFO, { title = "repossession.nvim" })
    end


    local function copy_session()
        local new_name = input("Copied session name: ")
        if new_name == nil then
            vim.notify("Copy cancelled", vim.log.levels.INFO, { title = "repossession.nvim" })
            return
        end

        local new_session_file = get_new_session_path(new_name)
        local session_name = get_session_name(new_session_file)
        if vim.fn.filereadable(new_session_file) == 1 then
            vim.notify("Session [" .. session_name .. "] already exists", vim.log.levels.WARN, { title = "repossession.nvim" })
            return
        end

        vim.api.nvim_win_close(win, true)

        if opts.tidy_sessions then
            local dir = vim.fn.fnamemodify(new_session_file, ":h")
            ensure_tidy_dir(dir)
        end

        local new_shada_file = new_session_file:gsub("%.vim$", ".shada")
        safe_mksession(new_session_file)
        activate_shada(new_shada_file)
        activate_session(new_session_file, nil)

        vim.notify("Copied session to [" .. session_name .. "]", vim.log.levels.INFO, { title = "repossession.nvim" })
        rerender()
    end


    local function rename_session(idx)
        local s = sessions[idx]
        if not s or s.git then
            vim.notify("Git sessions cannot be renamed", vim.log.levels.WARN, { title = "repossession.nvim" })
            return
        end

        local new_name = input("Rename session to: ")
        if new_name == nil then
            vim.notify("Rename cancelled", vim.log.levels.INFO, { title = "repossession.nvim" })
            return
        end

        local new_session_file = get_new_session_path(new_name)
        local session_name = get_session_name(new_session_file)
        if vim.fn.filereadable(new_session_file) == 1 then
            vim.notify("Session [" .. session_name .. "] already exists", vim.log.levels.WARN, { title = "repossession.nvim" })
            return
        end

        vim.api.nvim_win_close(win, true)

        local ok, err = os.rename(s.session_file, new_session_file)
        if not ok then
            vim.notify("Failed to rename session file: " .. err, vim.log.levels.ERROR, { title = "repossession.nvim" })
            return
        end

        local new_shada_file = new_session_file:gsub("%.vim$", ".shada")
        local old_shada_file = s.session_file:gsub("%.vim$", ".shada")
        if vim.fn.filereadable(old_shada_file) == 1 then
            ok, err = os.rename(old_shada_file, new_shada_file)
            if not ok then
                vim.notify("Failed to rename shada file: " .. err, vim.log.levels.ERROR, { title = "repossession.nvim" })
                return
            end
        end

        if s.session_file == last_session_file then
            last_session_file = new_session_file
        end

        if s.session_file == active_session_file then
            activate_shada(new_shada_file)
            activate_session(new_session_file, nil, {
                track_history = false,
                flush_path = new_session_file,
            })
            vim.notify("Renamed current session to [" .. session_name .. "]", vim.log.levels.INFO, { title = "repossession.nvim" })
        else
            vim.notify("Renamed session to [" .. session_name .. "]", vim.log.levels.INFO, { title = "repossession.nvim" })
        end
        rerender()
    end


    local function delete_session(idx)
        local s = sessions[idx]
        if not s or s.git then
            vim.notify("Git sessions cannot be deleted", vim.log.levels.WARN, { title = "repossession.nvim" })
            return
        end

        if s.session_file == active_session_file then
            vim.notify("Cannot delete the active session", vim.log.levels.WARN, { title = "repossession.nvim" })
            return
        end

        local session_name = get_session_name(s.session_file)
        local confirm = input("Delete session [" .. session_name .. "]? (y/n): ")
        if confirm == nil or confirm:lower() ~= "y" then
            vim.notify("Delete cancelled", vim.log.levels.INFO, { title = "repossession.nvim" })
            return
        end

        vim.api.nvim_win_close(win, true)

        local ok, err = os.remove(s.session_file)
        if not ok then
            vim.notify("Failed to delete session file: " .. err, vim.log.levels.ERROR, { title = "repossession.nvim" })
            return
        end

        local shada_file = s.session_file:gsub("%.vim$", ".shada")
        if vim.fn.filereadable(shada_file) == 1 then
            ok, err = os.remove(shada_file)
            if not ok then
                vim.notify("Failed to delete shada file: " .. err, vim.log.levels.ERROR, { title = "repossession.nvim" })
                return
            end
        end

        if s.session_file == last_session_file then
            last_session_file, last_git_root = nil, nil
        end

        vim.notify("Deleted session [" .. session_name .. "]", vim.log.levels.INFO, { title = "repossession.nvim" })
        rerender()
    end


    -- Keymaps
    vim.keymap.set("n", "q",     function() vim.api.nvim_win_close(win, true)                   end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<Esc>", function() vim.api.nvim_win_close(win, true)                   end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<C-c>", function() vim.api.nvim_win_close(win, true)                   end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "<CR>",  function() load_session(vim.api.nvim_win_get_cursor(win)[1])   end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "n",     function() new_session()                                       end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "c",     function() copy_session()                                      end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "r",     function() rename_session(vim.api.nvim_win_get_cursor(win)[1]) end, { buffer = buf, nowait = true })
    vim.keymap.set("n", "d",     function() delete_session(vim.api.nvim_win_get_cursor(win)[1]) end, { buffer = buf, nowait = true })
end



local function session_init()
    local session_file = nil
    local shada_file = opts.global_shada_file
    local sentinel_arg = nil

    local git_root = vim.fn.systemlist("git -C " .. vim.fn.shellescape(cwd) .. " rev-parse --show-toplevel")[1] or nil
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
            local dir = opts.tidy_dir .. "/" .. vim.fn.sha256(cwd):sub(1, 8)
            ensure_tidy_dir(dir)
            session_file = dir .. "/session" .. suffix .. ".vim"
            shada_file   = dir .. "/session" .. suffix .. ".shada"
        else
            -- store in cwd with a dot prefix
            session_file = cwd .. "/.session" .. suffix .. ".vim"
            shada_file   = cwd .. "/.session" .. suffix .. ".shada"
        end

        sentinel_arg = arg0
    else
        -- no session, global shada
    end

    -- Load shada
    activate_shada(shada_file)

    -- Load session
    if session_file then
        activate_session(session_file, git_sentinel_arg and git_root or nil)

        -- Wipe sentinel buffer after session has loaded
        if sentinel_arg then
            local sentinel_buf = vim.fn.bufnr(sentinel_arg)
            if sentinel_buf ~= -1 then
                vim.api.nvim_buf_delete(sentinel_buf, { force = true })
            end
        end
    end
end


function M.setup(user_opts)
    opts = vim.tbl_deep_extend("force", M.defaults, user_opts or {})

    -- Guards
    if opts.git_sentinel == opts.local_sentinel then
        vim.notify(
            "git_sentinel and local_sentinel must be different",
            vim.log.levels.ERROR,
            { title = "repossession.nvim" }
        )
        return
    end

    -- Commands
    vim.api.nvim_create_user_command("Repossession", repossession, {
        desc = "Browse, load, and modify available sessions for the current context",
        nargs = "?",
        complete = function(ArgLead, CmdLine, CursorPos)
            if CmdLine:match("^%s*Repossession%s+%S*$") == nil then
                return {}
            end
            return vim.tbl_filter(function(c)
                return vim.startswith(c, ArgLead)
            end, { "last" })
        end,
    })

    -- Helpers
    local function lazy_busy()
        local ok, view = pcall(require, "lazy.view")
        return ok and view.visible ~= nil and view.visible() or false
    end

    -- Initialize
    vim.api.nvim_create_autocmd("VimEnter", {
        desc = "Initialize vim session",
        group = repossession_group,
        nested = true,
        callback = function()
            if not lazy_busy() then
                session_init()
                return
            end

            -- lazy is showing its float; wait for it to close
            local timer = assert(vim.uv.new_timer())
            timer:start(100, 100, vim.schedule_wrap(function()
                if not lazy_busy() then
                    timer:stop()
                    timer:close()
                    session_init()
                end
            end))
        end,
    })
end


return M

