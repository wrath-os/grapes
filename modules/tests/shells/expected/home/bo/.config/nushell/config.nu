# Written by wrath from the configuration; changes here are replaced.
$env.config = ($env.config | merge deep {
  "show_banner": false
})
alias ll = ls -l
