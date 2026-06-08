# repossession.nvim
Automatic session management based on how you launch Neovim.


## Behavior

| Invocation | Session | Shada |
|---|---|---|
| `nvim ,` inside a git repo | `.git/session.vim` | `.git/session.shada` |
| `nvim =` | `<hash>/session.vim` | `<hash>/session.shada` |
| `nvim =foo` | `<hash>/session_foo.vim` | `<hash>/session_foo.shada` |
| `nvim` (no args) | none | global shada |
| `nvim <file>` | none | global shada |

Each session mode is triggered by a sentinel argument. The git sentinel (`,` by
default) activates a git session when inside a git repo. The local sentinel
(`=` by default) activates a local session anywhere — optionally followed by a
name to maintain multiple named sessions in the same directory. Neither sentinel
ever appears as an open buffer — both are cleaned up immediately after the
session loads. Sentinels can be changed via the `git_sentinel` and
`local_sentinel` config options. The two sentinels must be different.

The git-project case stores both the session and shada inside `.git/`, so they
are never tracked by git and are naturally scoped to the repository root
regardless of which subdirectory you launched from. Local sessions similarly
store their shada alongside the session file, keeping all state fully isolated
per session.


## Commands

| Command | Description |
|---|---|
| `:Repossession` | Open the session picker for the current context |
| `:Repossession last` | Toggle to the last opened session |

The picker lists the git session (if inside a git repo) and all local sessions
for the current directory. Session saving transfers automatically to the newly
loaded session.

| Key | Action |
|---|---|
| `<CR>` | Load the selected session |
| `n` | Create a new session |
| `c` | Copy current session |
| `r` | Rename the selected session |
| `d` | Delete the selected session |
| `q` / `<Esc>` | Close the picker |

- Git sessions cannot be renamed or deleted from the picker.
- When creating or renaming a session, leaving the name blank creates or renames to the default session.


## Storage location

By default (`tidy_sessions = true`), local sessions are stored under `tidy_dir`
(Neovim's data directory by default), in a folder named after a hash of the cwd:

```
~/.local/share/nvim/repossession/<hash>/
├── SESSIONPATH        (the cwd this hash corresponds to)
├── session.vim
├── session.shada
├── session_foo.vim
└── session_foo.shada
```

All sessions launched from the same directory share one hash folder. The
`SESSIONPATH` file records the originating path so the folder can be identified
later. This keeps your working directories free of session files entirely.

Set `tidy_sessions = false` to instead write local sessions to the current
working directory as dotfiles (`.session.vim`, `.session_foo.vim`, and their
`.shada` counterparts).

Note that `tidy_dir` only governs tidied local sessions; `global_shada_file` is
configured independently, so the global shada can be pinned to its own location
regardless of where tidied sessions are stored.


## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
    "liamrlawrence/repossession.nvim",

    config = function()
        require("repossession").setup()

        vim.keymap.set("n", "<leader>rp", "<cmd>Repossession<cr>",      { desc = "Session manager" })
        vim.keymap.set("n", "<leader>rl", "<cmd>Repossession last<cr>", { desc = "Toggle to last session" })
    end,
}
```


## Configuration

Default values:

```lua
require("repossession").setup({
    local_sentinel    = "=",
    git_sentinel      = ",",
    git_session_file  = ".git/session.vim",
    git_shada_file    = ".git/session.shada",
    global_shada_file = vim.fn.stdpath("data") .. "/repossession/global.shada",
    tidy_dir          = vim.fn.stdpath("data") .. "/repossession",
    tidy_sessions     = true,
})
```


## Recommendations

If using `tidy_sessions = false`, add repossession's local session files to your
global gitignore so they do not show up as untracked files in git projects:

```sh
echo ".session*.vim"   >> ~/.config/git/ignore
echo ".session*.shada" >> ~/.config/git/ignore
```

With the default `tidy_sessions = true` this is unnecessary, since nothing is
written to your working directories.


## License

repossession.nvim is released under the MIT license.

