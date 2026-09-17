# Apple Foundation Model completion for zsh's line editor.
# Source this file, then call apple-fm-enable. No shell command is executed by
# this plugin; accepting a suffix only edits LBUFFER.

typeset -g APPLE_FM_DEBOUNCE=${APPLE_FM_DEBOUNCE:-0.35}
typeset -g APPLE_FM_TRIGGER=${APPLE_FM_TRIGGER:-'^X^F'}
typeset -g APPLE_FM_COMMAND=${APPLE_FM_COMMAND:-/usr/bin/fm}
typeset -g _APPLE_FM_ENABLED=0
typeset -g _APPLE_FM_SEQ=0
typeset -g _APPLE_FM_SCHEDULED=-1
typeset -g _APPLE_FM_FD=-1
typeset -g _APPLE_FM_PID=-1
typeset -g _APPLE_FM_TIMER_FD=-1
typeset -g _APPLE_FM_TIMER_PID=-1
typeset -g _APPLE_FM_SUGGESTION=''
typeset -g _APPLE_FM_STATE=''
typeset -g _APPLE_FM_TAB_EMACS=''
typeset -g _APPLE_FM_TAB_VIINS=''
typeset -g _APPLE_FM_ESC_EMACS=''

function _apple_fm_state() {
  # The state includes the working directory and cursor position. The cursor
  # is intentionally supported only at the end of the line for this preview.
  local sep=$'\x1f'
  print -rn -- "${PWD}${sep}${LBUFFER}${sep}${RBUFFER}${sep}${CURSOR}"
}

function _apple_fm_clear() {
  _APPLE_FM_SUGGESTION=''
  POSTDISPLAY=''
  zle && zle -R 2>/dev/null
}

function _apple_fm_close_fd() {
  if (( _APPLE_FM_FD >= 0 )); then
    zle -F $_APPLE_FM_FD 2>/dev/null
    exec {_APPLE_FM_FD}<&- 2>/dev/null
    _APPLE_FM_FD=-1
  fi
  if (( _APPLE_FM_PID > 0 )); then kill $_APPLE_FM_PID 2>/dev/null; _APPLE_FM_PID=-1; fi
}

function _apple_fm_close_timer() {
  if (( _APPLE_FM_TIMER_FD >= 0 )); then
    zle -F $_APPLE_FM_TIMER_FD 2>/dev/null
    exec {_APPLE_FM_TIMER_FD}<&- 2>/dev/null
    _APPLE_FM_TIMER_FD=-1
  fi
  if (( _APPLE_FM_TIMER_PID > 0 )); then kill $_APPLE_FM_TIMER_PID 2>/dev/null; _APPLE_FM_TIMER_PID=-1; fi
}

function _apple_fm_show() {
  if [[ -n $_APPLE_FM_SUGGESTION ]]; then
    # POSTDISPLAY is rendered after the editable buffer. Dim ANSI escapes are
    # display-only and never enter LBUFFER when the suffix is accepted.
    POSTDISPLAY=$'\e[2m'${_APPLE_FM_SUGGESTION}$'\e[0m'
  else
    POSTDISPLAY=''
  fi
  zle && zle -R 2>/dev/null
}

function _apple_fm_response() {
  local fd=$1 response current
  # Read through EOF. fm is requested in --no-stream mode and this also lets
  # us reject any response containing a newline rather than showing a prefix.
  IFS= read -r -d '' -u $fd response 2>/dev/null || true
  # EOF delivery makes zsh read return nonzero; retain its data and remove
  # only the transport newline emitted by fm.
  response=${response%$'\n'}
  _apple_fm_close_fd
  current=$(_apple_fm_state)
  [[ $current == $_APPLE_FM_STATE ]] || return 0
  # Control bytes and multiline output are never safe terminal insertions.
  [[ $response != *$'\n'* && $response != *$'\r'* ]] || { _apple_fm_clear; return 0; }
  [[ $response != *$'\e'* && $response != *$'\001'* && $response != *$'\002'* ]] || { _apple_fm_clear; return 0; }
  _APPLE_FM_SUGGESTION=$response
  _apple_fm_show
}

function _apple_fm_request() {
  local expected=$1 prompt instructions fd
  (( _APPLE_FM_ENABLED )) || return 0
  [[ $CURSOR -eq ${#LBUFFER} && -z $RBUFFER ]] || { _apple_fm_clear; return 0; }
  [[ -n $LBUFFER ]] || { _apple_fm_clear; return 0; }
  _apple_fm_close_fd
  _apple_fm_clear
  instructions='Complete only the missing suffix of this zsh command line. Return only a single-line suffix, without explanation, code fences, repetition of the supplied prefix, or execution instructions.'
  prompt=$'Shell: zsh\nWorking directory: '"${PWD}"$'\nCommand prefix:\n'"${LBUFFER}"$'\n\nReturn the suffix only.'
  exec {fd}< <(print -rn -- "$prompt" | "$APPLE_FM_COMMAND" respond --model system --no-stream --greedy --instructions "$instructions" 2>/dev/null)
  _APPLE_FM_FD=$fd
  _APPLE_FM_PID=$!
  _APPLE_FM_STATE=$expected
  zle -F $fd _apple_fm_response
}

function _apple_fm_debounce() {
  local fd=$1 seq
  IFS= read -r seq <&$fd 2>/dev/null || true
  _apple_fm_close_timer
  (( seq == _APPLE_FM_SEQ )) || return 0
  _APPLE_FM_SCHEDULED=-1
  _apple_fm_request "$(_apple_fm_state)"
}

function _apple_fm_pre_redraw() {
  (( _APPLE_FM_ENABLED )) || return 0
  local state=$(_apple_fm_state)
  if [[ $state != $_APPLE_FM_STATE ]]; then
    (( ++_APPLE_FM_SEQ ))
    _apple_fm_clear
    if [[ $CURSOR -eq ${#LBUFFER} && -z $RBUFFER && -n $LBUFFER && $_APPLE_FM_SCHEDULED -ne $_APPLE_FM_SEQ ]]; then
      _apple_fm_close_timer
      _APPLE_FM_SCHEDULED=$_APPLE_FM_SEQ
      local timer_fd
      exec {timer_fd}< <(sleep $APPLE_FM_DEBOUNCE; print -r -- $_APPLE_FM_SEQ)
      _APPLE_FM_TIMER_FD=$timer_fd
      _APPLE_FM_TIMER_PID=$!
      zle -F $timer_fd _apple_fm_debounce
    fi
    _APPLE_FM_STATE=$state
  fi
}

function fm-suggest() {
  _apple_fm_request "$(_apple_fm_state)"
}

function _apple_fm_tab() {
  if [[ -n $_APPLE_FM_SUGGESTION && $(_apple_fm_state) == $_APPLE_FM_STATE ]]; then
    LBUFFER+=${_APPLE_FM_SUGGESTION}
    _apple_fm_clear
  else
    if [[ $KEYMAP == vicmd ]]; then
      zle "${_APPLE_FM_TAB_EMACS:-expand-or-complete}"
    elif [[ $KEYMAP == viins ]]; then
      zle "${_APPLE_FM_TAB_VIINS:-expand-or-complete}"
    else
      zle "${_APPLE_FM_TAB_EMACS:-expand-or-complete}"
    fi
  fi
}

function _apple_fm_escape() { _apple_fm_clear; }
zle -N fm-suggest
zle -N apple-fm-tab _apple_fm_tab
zle -N apple-fm-dismiss _apple_fm_escape

function apple-fm-enable() {
  (( _APPLE_FM_ENABLED )) && return 0
  _APPLE_FM_TAB_EMACS=${${(z)$(bindkey -M emacs '^I')}[2]}
  _APPLE_FM_TAB_VIINS=${${(z)$(bindkey -M viins '^I')}[2]}
  _APPLE_FM_ESC_EMACS=${${(z)$(bindkey -M emacs '^[')}[2]}
  [[ -n $_APPLE_FM_TAB_EMACS ]] || _APPLE_FM_TAB_EMACS=expand-or-complete
  [[ -n $_APPLE_FM_TAB_VIINS ]] || _APPLE_FM_TAB_VIINS=expand-or-complete
  bindkey -M emacs '^I' apple-fm-tab
  bindkey -M viins '^I' apple-fm-tab
  bindkey -M emacs '^[' apple-fm-dismiss
  bindkey "$APPLE_FM_TRIGGER" fm-suggest
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget -d zle-line-pre-redraw _apple_fm_pre_redraw 2>/dev/null
  add-zle-hook-widget zle-line-pre-redraw _apple_fm_pre_redraw
  _APPLE_FM_ENABLED=1
}

function apple-fm-disable() {
  (( _APPLE_FM_ENABLED )) || return 0
  _apple_fm_close_fd
  _apple_fm_close_timer
  (( ++_APPLE_FM_SEQ ))
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget -d zle-line-pre-redraw _apple_fm_pre_redraw 2>/dev/null
  bindkey -M emacs '^I' "${_APPLE_FM_TAB_EMACS:-expand-or-complete}"
  bindkey -M viins '^I' "${_APPLE_FM_TAB_VIINS:-expand-or-complete}"
  bindkey -M emacs '^[' "${_APPLE_FM_ESC_EMACS:-undefined-key}"
  _apple_fm_clear
  _APPLE_FM_ENABLED=0
}

function apple-fm-remove() { apple-fm-disable; unfunction apple-fm-enable apple-fm-disable apple-fm-remove fm-suggest 2>/dev/null; }
