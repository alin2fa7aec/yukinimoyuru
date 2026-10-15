# env.nu
#
# Loaded before config.nu and login.nu.
# See https://www.nushell.sh/book/configuration.html

# alias
alias vi = vim
alias grep = rg
alias find = fd
alias diff = delta
alias ls = ^eza --icons --git --group-directories-first
alias ll = ^eza --icons --git --group-directories-first -lbhF
alias la = ^eza --icons --git --group-directories-first -labhF
alias lt = ^eza --tree --icons --level=2
alias 'git st' = ^git status
alias 'git sw' = ^git switch
alias 'git re' = ^git restore
alias 'git br' = ^git branch
alias 'git logol' = ^git log --oneline
def 'git frestore' [path: string] {
  git restore --staged $path
  git restore $path
}

# path
use std/util "path add"
path add ($env.HOME | path join ".local/bin")
