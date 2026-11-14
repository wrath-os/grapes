# Written by wrath from the configuration; changes here are replaced.
HISTFILE=$HOME/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
autoload -Uz compinit && compinit
setopt share_history
alias ll='ls -l'
alias say='echo '\''hi'\'''
bindkey -e
