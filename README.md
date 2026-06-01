# repossession.nvim
Automatic session management based on how you launch Neovim.

## Behavior
| Invocation | Session | Shada |
|---|---|---|
| `nvim ,` inside a git repo | `.git/session.vim` | `.git/session.shada` |
| `nvim =` | `.session.vim` in cwd | `.session.shada` in cwd |
| `nvim =foo` | `.session_foo.vim` in cwd | `.session_foo.shada` in cwd |
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
store their shada alongside the session file in the cwd, keeping all state
fully isolated per session.

## Installation
Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
    "liamrlawrence/repossession.nvim",

    config = function()
        require("repossession").setup()
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
})
```

## Recommendations
Add repossession's local session files to your global gitignore so they do not
show up as untracked files in git projects:

```sh
echo ".session*.vim" >> ~/.config/git/ignore
echo ".session*.shada" >> ~/.config/git/ignore
```

## License
repossession.nvim is released under the MIT license.

