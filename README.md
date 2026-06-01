# repossession.nvim
Automatic session management based on how you launch Neovim.

## Behavior
| Invocation | Session | Shada |
|---|---|---|
| `nvim ,` inside a git repo | `.git/session.vim` | `.git/session.shada` |
| `nvim` (no args) | `.session.vim` in cwd | global shada |
| `nvim <file>` | none | global shada |

The git-project case stores both the session and shada inside `.git/`, so they are never tracked by git and are naturally scoped to the repository root regardless of which subdirectory you launched from.

The git sentinel (`,` by default) is a special argument used to trigger the git session. It is wiped immediately after the session loads and never appears as a buffer. The sentinel can be changed via the `git_sentinel` config option.

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
    local_session_file = ".session.vim",
    global_shada_file  = vim.fn.stdpath("data") .. "/repossession/global.shada",
})
```

## Recommendations
Add `.session.vim` to your global gitignore so local sessions do not show up as untracked files in git projects:
```
echo ".session.vim" >> ~/.config/git/ignore
```

## License
repossession.nvim is released under the MIT license.

