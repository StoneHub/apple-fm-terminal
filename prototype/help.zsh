# Throwaway shell bridge, loaded only by ./terminal-help's disposable shell.
# It is deliberately separate from the installed suffix-completion plugin.
[[ -o interactive && -t 0 && -n ${_FMH_SOCKET:-} ]] || return 0
bindkey -e
setopt no_prompt_sp
PS1='FM Ask %~ %# '
typeset -g _FMH_COMMAND='' _FMH_CWD='' _FMH_BEFORE='' _FMH_FROM_ASK=0
typeset -g _FMH_MISSING=0 _FMH_PASTED=0 _FMH_ACTIVE=0
typeset -g _FMH_ALLOW_ASK=0

_fmh_marker() {
  emulate -L zsh
  local kind=$1 line=${2:-} code=${3:-0} directory=$PWD
  line=${line//$'\a'/}; directory=${directory//$'\a'/}
  print -rn -- $'\e]777;'"$_FMH_TOKEN;$kind"$'\0'"$directory"$'\0'"${line[1,2000]}"$'\0'"$code"$'\a'
}

_fmh_dismiss() {
  _FMH_COMMAND=''; POSTDISPLAY=''
}

_fmh_preexec() {
  emulate -L zsh
  setopt extendedglob
  _FMH_MISSING=0; _FMH_ACTIVE=1; _FMH_ALLOW_ASK=0
  _fmh_dismiss
  local -a words=( ${(z)1} )
  if (( ! _FMH_PASTED )) && [[ ${words[1]:-} == ask && $1 != *$'\n'* ]]; then
    _FMH_ALLOW_ASK=1
    local word
    for word in "${words[@]}"; do
      # Quoted question text is data. Unquoted grammar makes this a script,
      # pipeline or compound command rather than a direct ask invocation.
      [[ $word == [\;\&\|\<\>\(\)\{\}]* ]] && _FMH_ALLOW_ASK=0
    done
  fi
  # Exclude help's own generated text from future evidence.
  if [[ ${words[1]:-} == (ask|_fmh_*) ]]; then
    _fmh_marker pause; _FMH_ACTIVE=0
  else
    _fmh_marker begin "$1"
  fi
  # An unresolved bare command, directly entered as one simple shell line.
  # Known scripts/functions/source/aliases, shell grammar and pastes never offer.
  if (( ! _FMH_PASTED && $#words )) && [[ $1 != *[$'\n;&|<>`$(){}']* && ${words[1]} != */* && ${words[1]} == [a-zA-Z_][a-zA-Z0-9_-]# ]]; then
    whence -- "${words[1]}" >/dev/null 2>&1 || _FMH_MISSING=1
  fi
  _FMH_PASTED=0
}

_fmh_precmd() {
  local code=$?
  (( _FMH_ACTIVE )) && _fmh_marker end '' "$code"
  _FMH_ACTIVE=0
  if (( code == 127 && _FMH_MISSING )); then
    print -r -- 'Apple FM: Ctrl-X then ? asks for help with this failure. No model has run.'
  fi
  _FMH_MISSING=0
  return 0
}

ask() {
  emulate -L zsh
  # A sourced script, function, substitution, pipeline or child shell must not
  # accidentally invoke inference. Direct typed ask and our ZLE widget only.
  local widget=0
  [[ ${funcstack[2]:-} == _fmh_help ]] && zle && widget=1
  if [[ ! -o interactive || $ZSH_SUBSHELL != 0 ]] || { (( ! widget )) && { [[ ! -t 0 || ! -t 1 || -n ${funcstack[2]:-} ]] || (( ! _FMH_ALLOW_ASK )); }; }; then
    print -u2 -r -- 'Apple FM: ask is only available directly at this interactive prompt.'
    return 2
  fi
  _fmh_marker pause
  _fmh_dismiss
  case ${1:-} in
    --help|-h)
      print -r -- 'ask "question"  •  ask (last command)  •  ask --context  •  ask --clear'
      print -r -- 'Ctrl-X then ? requests help; Tab inserts a preview; Enter executes; Escape dismisses.'
      return 0;;
    --context)
      "$_FMH_PYTHON" "$_FMH_HELPER" --client "$_FMH_SOCKET" context
      return $?;;
    --clear)
      local cleared
      cleared=$("$_FMH_PYTHON" "$_FMH_HELPER" --client "$_FMH_SOCKET" clear) || return $?
      print -r -- "${cleared#*$'\n'}"
      return 0;;
  esac
  print -r -- 'Apple FM: thinking locally… (typing or Ctrl-C cancels)'
  local result
  result=$("$_FMH_PYTHON" "$_FMH_HELPER" --client "$_FMH_SOCKET" ask "$*") || return $?
  _FMH_COMMAND=${result%%$'\n'*}
  print -r -- "${result#*$'\n'}"
  if [[ -n $_FMH_COMMAND ]]; then
    _FMH_CWD=$PWD; _FMH_FROM_ASK=1
    print -r -- "Proposed command: $_FMH_COMMAND"
    print -r -- 'Tab inserts it. Enter runs it separately. Escape dismisses.'
  fi
}

_fmh_help() {
  emulate -L zsh
  local before=$BUFFER old_pwd=$PWD
  zle -I
  ask "$before"
  if [[ $PWD == $old_pwd && $BUFFER == $before && -n $_FMH_COMMAND ]]; then
    _FMH_BEFORE=$before; _FMH_FROM_ASK=0
    POSTDISPLAY=$'  → '"$_FMH_COMMAND"
  else
    _fmh_dismiss
  fi
  zle -R
}

_fmh_line_init() {
  if (( _FMH_FROM_ASK )) && [[ $PWD == $_FMH_CWD && -z $BUFFER ]]; then
    _FMH_BEFORE=$BUFFER; _FMH_FROM_ASK=0
    POSTDISPLAY=$'  → '"$_FMH_COMMAND"
  else
    _fmh_dismiss
  fi
}

_fmh_redraw() {
  [[ $BUFFER == $_FMH_BEFORE && $PWD == $_FMH_CWD ]] || _fmh_dismiss
}

_fmh_tab() {
  if [[ -n $_FMH_COMMAND && $BUFFER == $_FMH_BEFORE && $PWD == $_FMH_CWD ]]; then
    BUFFER=$_FMH_COMMAND; CURSOR=${#BUFFER}
    _fmh_dismiss
  else
    zle expand-or-complete
  fi
}

_fmh_escape() { _fmh_dismiss; zle -R; }
_fmh_abort() { _fmh_dismiss; zle .send-break; }
_fmh_paste() { _fmh_dismiss; _FMH_PASTED=1; zle .bracketed-paste; }

autoload -Uz add-zsh-hook add-zle-hook-widget
add-zsh-hook preexec _fmh_preexec
add-zsh-hook precmd _fmh_precmd
zle -N _fmh_help; zle -N _fmh_tab; zle -N _fmh_escape; zle -N _fmh_abort; zle -N _fmh_paste
zle -N _fmh_line_init; zle -N _fmh_redraw
add-zle-hook-widget line-init _fmh_line_init
add-zle-hook-widget line-pre-redraw _fmh_redraw
bindkey '^X?' _fmh_help
bindkey '^I' _fmh_tab
bindkey '^[' _fmh_escape
bindkey '^C' _fmh_abort
bindkey '^[[200~' _fmh_paste

print -r -- 'Apple FM Ask prototype — disposable shell; exit returns to your original shell.'
print -r -- 'This session retains up to 5 commands and bounded output in memory. Nothing is saved.'
print -r -- 'Use ask "question" or Ctrl-X then ?. ask --context shows context; ask --clear forgets it.'
print -r -- 'Model requests are explicit. Tab accepts a command; Enter executes it separately.'
