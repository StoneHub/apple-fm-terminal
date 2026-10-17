# Apple FM help bridge. Loaded after the user's normal .zshrc settings.
[[ -o interactive && ${APPLE_FM_SESSION_PID:-0} == $$ && -S ${APPLE_FM_SESSION_SOCKET:-} ]] || return 0
[[ ${_FMH_ENABLED:-0} == 1 ]] && return 0
(( $+functions[fm-ask] )) && { print -u2 -- 'Apple FM: fm-ask already exists; leaving your bindings alone.'; return 0; }
typeset -g _FMH_SOCKET=$APPLE_FM_SESSION_SOCKET _FMH_TOKEN=$APPLE_FM_SESSION_TOKEN
typeset -g _FMH_HELPER=$APPLE_FM_SESSION_PROGRAM _FMH_PYTHON=$APPLE_FM_SESSION_PYTHON
typeset -g _FMH_ROOT=${_FMH_HELPER:h} _FMH_ENABLED=1 _FMH_OWN_PREVIEW=0
typeset -g _FMH_EXPECTED_DISPLAY='' _FMH_PREVIOUS_DISPLAY=''
typeset -gA _FMH_BINDINGS
typeset +x APPLE_FM_SESSION_SOCKET APPLE_FM_SESSION_TOKEN APPLE_FM_SESSION_PROGRAM APPLE_FM_SESSION_PYTHON
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
  emulate -L zsh
  _FMH_COMMAND=''
  if (( _FMH_OWN_PREVIEW )) && [[ $POSTDISPLAY == $_FMH_EXPECTED_DISPLAY ]]; then
    POSTDISPLAY=$_FMH_PREVIOUS_DISPLAY
  fi
  _FMH_OWN_PREVIEW=0
}

_fmh_preexec() {
  emulate -L zsh
  setopt extendedglob
  _FMH_MISSING=0; _FMH_ACTIVE=1; _FMH_ALLOW_ASK=0
  _fmh_dismiss
  local -a words=( ${(z)1} )
  if (( ! _FMH_PASTED )) && [[ ${words[1]:-} == (ask|fm-ask) && $1 != *$'\n'* ]]; then
    _FMH_ALLOW_ASK=1
    local word
    for word in "${words[@]}"; do
      # Quoted question text is data. Unquoted grammar makes this a script,
      # pipeline or compound command rather than a direct ask invocation.
      [[ $word == [\;\&\|\<\>\(\)\{\}]* ]] && _FMH_ALLOW_ASK=0
    done
  fi
  # Exclude help's own generated text from future evidence.
  local executable=${words[1]:-}
  executable=${executable:t}
  if [[ $executable == (ask|fm-ask|apple-fm-terminal|_fmh_*|ssh|zsh|bash|fish|tmux|screen|vim|nvim|nano|less|more|top|htop) ]]; then
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
  emulate -L zsh
  (( _FMH_ACTIVE )) && _fmh_marker end '' "$code"
  _FMH_ACTIVE=0
  if (( code == 127 && _FMH_MISSING )); then
    print -r -- 'Apple FM: Ctrl-X then ? asks for help with this failure. No model has run.'
  fi
  _FMH_MISSING=0
  return 0
}

fm-ask() {
  emulate -L zsh
  # A sourced script, function, substitution, pipeline or child shell must not
  # accidentally invoke inference. Direct typed ask and our ZLE widget only.
  local widget=0 direct=0
  [[ -z ${funcstack[2]:-} || ( ${funcstack[2]:-} == ask && -z ${funcstack[3]:-} ) ]] && direct=1
  [[ ${funcstack[2]:-} == _fmh_help ]] && zle && widget=1
  if [[ ! -o interactive || $ZSH_SUBSHELL != 0 ]] || { (( ! widget )) && { [[ ! -t 0 || ! -t 1 ]] || (( ! direct )) || (( ! _FMH_ALLOW_ASK )); }; }; then
    print -u2 -r -- 'Apple FM: ask is only available directly at this interactive prompt.'
    return 2
  fi
  _fmh_marker pause
  _fmh_dismiss
  case ${1:-} in
    --help|-h)
      print -r -- 'ask "question"  •  ask (last command)  •  ask --context  •  ask --clear  •  ask --pause  •  ask --resume'
      print -r -- 'Ctrl-X then ? requests help; Tab inserts a preview; Enter executes; Escape dismisses.'
      return 0;;
    --context)
      "$_FMH_PYTHON" "$_FMH_HELPER" --client "$_FMH_SOCKET" context
      return $?;;
    --clear|--pause|--resume)
      local cleared
      cleared=$("$_FMH_PYTHON" "$_FMH_HELPER" --client "$_FMH_SOCKET" "${1#--}") || return $?
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
  fm-ask "$before"
  if [[ $PWD == $old_pwd && $BUFFER == $before && -n $_FMH_COMMAND ]]; then
    _FMH_BEFORE=$before; _FMH_FROM_ASK=0
    _fmh_preview
  else
    _fmh_dismiss
  fi
  zle -R
}

_fmh_line_init() {
  emulate -L zsh
  if (( _FMH_FROM_ASK )) && [[ $PWD == $_FMH_CWD && -z $BUFFER ]]; then
    _FMH_BEFORE=$BUFFER; _FMH_FROM_ASK=0
    _fmh_preview
  else
    _fmh_dismiss
  fi
}

_fmh_redraw() {
  emulate -L zsh
  if (( _FMH_OWN_PREVIEW )) && [[ ${POSTDISPLAY:-} != $_FMH_EXPECTED_DISPLAY ]]; then
    _FMH_OWN_PREVIEW=0; _FMH_COMMAND=''
  fi
  [[ $BUFFER == $_FMH_BEFORE && $PWD == $_FMH_CWD ]] || _fmh_dismiss
}

_fmh_tab() {
  emulate -L zsh
  if [[ -n $_FMH_COMMAND && $BUFFER == $_FMH_BEFORE && $PWD == $_FMH_CWD ]]; then
    BUFFER=$_FMH_COMMAND; CURSOR=${#BUFFER}
    _fmh_dismiss
  else
    _fmh_original tab
  fi
}

_fmh_preview() {
  emulate -L zsh
  if [[ -n $POSTDISPLAY ]] && (( ! _FMH_OWN_PREVIEW )); then
    _FMH_COMMAND=''
    zle -M 'Apple FM: another completion owns the preview; proposal was not armed for Tab.'
    return
  fi
  _FMH_PREVIOUS_DISPLAY=$POSTDISPLAY
  _FMH_EXPECTED_DISPLAY=$'  → '"$_FMH_COMMAND"
  POSTDISPLAY=$_FMH_EXPECTED_DISPLAY; _FMH_OWN_PREVIEW=1
}
_fmh_original() {
  emulate -L zsh
  local keymap=${KEYMAP:-emacs} key=$1 original mapping
  if [[ $keymap == main ]]; then
    mapping=$(bindkey -lL main)
    keymap=${${(z)mapping}[3]:-emacs}
  fi
  original=${_FMH_BINDINGS[$keymap:$key]:-undefined-key}
  [[ $original != _fmh_* ]] && zle "$original"
}
_fmh_escape() {
  if [[ -n $_FMH_COMMAND ]]; then _fmh_dismiss; zle -R
  else _fmh_original escape; fi
}
_fmh_abort() { _fmh_dismiss; _fmh_original abort; }
_fmh_paste() { _fmh_dismiss; _FMH_PASTED=1; _fmh_original paste; }

apple-fm-help-disable() {
  emulate -L zsh
  _fmh_marker pause; _fmh_dismiss
  autoload -Uz add-zsh-hook add-zle-hook-widget
  add-zsh-hook -d preexec _fmh_preexec; add-zsh-hook -d precmd _fmh_precmd
  add-zle-hook-widget -d line-init _fmh_line_init
  add-zle-hook-widget -d line-pre-redraw _fmh_redraw
  local keymap key sequence widget binding
  for keymap in emacs viins; do
    for key sequence widget in tab '^I' _fmh_tab escape '^[' _fmh_escape abort '^C' _fmh_abort paste '^[[200~' _fmh_paste help '^X?' _fmh_help; do
      binding=$(bindkey -M "$keymap" "$sequence")
      [[ ${${(z)binding}[2]} == $widget ]] && bindkey -M "$keymap" "$sequence" "${_FMH_BINDINGS[$keymap:$key]}"
    done
  done
  [[ ${functions[ask]:-} == 'fm-ask "$@"' ]] && unfunction ask
  unfunction fm-ask
  _FMH_ENABLED=0
}

autoload -Uz add-zsh-hook add-zle-hook-widget
add-zsh-hook preexec _fmh_preexec
add-zsh-hook precmd _fmh_precmd
zle -N _fmh_help; zle -N _fmh_tab; zle -N _fmh_escape; zle -N _fmh_abort; zle -N _fmh_paste
zle -N _fmh_line_init; zle -N _fmh_redraw
add-zle-hook-widget line-init _fmh_line_init
add-zle-hook-widget line-pre-redraw _fmh_redraw
() {
  emulate -L zsh
  local keymap key sequence widget binding
  for keymap in emacs viins; do
    for key sequence widget in tab '^I' _fmh_tab escape '^[' _fmh_escape abort '^C' _fmh_abort paste '^[[200~' _fmh_paste help '^X?' _fmh_help; do
      binding=$(bindkey -M "$keymap" "$sequence")
      _FMH_BINDINGS[$keymap:$key]=${${(z)binding}[2]}
      bindkey -M "$keymap" "$sequence" "$widget"
    done
  done
}
if ! whence ask >/dev/null 2>&1; then
  functions[ask]='fm-ask "$@"'
fi
if ! whence apple-fm-terminal >/dev/null 2>&1; then
  apple-fm-terminal() { "$_FMH_PYTHON" "$_FMH_ROOT/scripts/management.py" "$@"; }
fi
