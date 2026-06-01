# repossession.nvim
Automatic session management based on how you launch Neovim.

## Behavior
| Invocation | Session | Shada |
|---|---|---|
| `nvim ,` inside a git repo | `.git/session.vim` | `.git/session.shada` |
| `nvim =` | `.session.vim` in cwd | global shada |
| `nvim` (no args) | none | global shada |
| `nvim <file>` | none | global shada |

Each session mode is triggered by a sentinel argument. The git sentinel (`,` by
default) activates a git session when inside a git repo. The local sentinel
(`=` by default) activates a local session anywhere. Both are wiped immediately
after the session loads and never appear as a buffer. Sentinels can be changed
via the `git_sentinel` and `local_sentinel` config options.

The git-project case stores both the session and shada inside `.git/`, so they
are never tracked by git and are naturally scoped to the repository root
regardless of which subdirectory you launched from.

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
    git_sentinel       = ",",
    git_session_file   = ".git/session.vim",
    git_shada_file     = ".git/session.shada",
    local_sentinel     = "=",
    local_session_file = ".session.vim",
    global_shada_file  = vim.fn.stdpath("data") .. "/repossession/global.shada",
})
```

## Recommendations
Add `.session.vim` to your global gitignore so local sessions do not show up as untracked files in git projects:
```sh
echo ".session.vim" >> ~/.config/git/ignore
```

## License
repossession.nvim is released under the MIT license.

