# Apple FM completion: asynchronous, request-scoped, and non-executing.
zmodload zsh/zselect zsh/system
typeset -g APPLE_FM_DEBOUNCE=${APPLE_FM_DEBOUNCE:-0.35} APPLE_FM_TIMEOUT=${APPLE_FM_TIMEOUT:-15}
typeset -g APPLE_FM_CONTEXT_CAP=${APPLE_FM_CONTEXT_CAP:-6000} APPLE_FM_TRIGGER=${APPLE_FM_TRIGGER:-'^X^F'}
typeset -g APPLE_FM_COMMAND=${APPLE_FM_COMMAND:-/usr/bin/fm} _APPLE_FM_ENABLED=${_APPLE_FM_ENABLED:-0}
typeset -g _APPLE_FM_GENERATION=${_APPLE_FM_GENERATION:-0} _APPLE_FM_OBSERVED=${_APPLE_FM_OBSERVED:-}
typeset -g _APPLE_FM_DISMISSED=${_APPLE_FM_DISMISSED:-} _APPLE_FM_REQUEST_STATE=${_APPLE_FM_REQUEST_STATE:-}
typeset -g _APPLE_FM_REQUEST_GEN=${_APPLE_FM_REQUEST_GEN:--1} _APPLE_FM_EXPLICIT=${_APPLE_FM_EXPLICIT:-0}
typeset -g _APPLE_FM_FD=${_APPLE_FM_FD:--1} _APPLE_FM_PID=${_APPLE_FM_PID:--1} _APPLE_FM_FILE=${_APPLE_FM_FILE:-}
typeset -g _APPLE_FM_TIMER_FD=${_APPLE_FM_TIMER_FD:--1} _APPLE_FM_TIMER_PID=${_APPLE_FM_TIMER_PID:--1}
typeset -g _APPLE_FM_TIMEOUT_FD=${_APPLE_FM_TIMEOUT_FD:--1} _APPLE_FM_TIMEOUT_PID=${_APPLE_FM_TIMEOUT_PID:--1}
typeset -g _APPLE_FM_SUGGESTION=${_APPLE_FM_SUGGESTION:-} _APPLE_FM_REGION_SAVED=${_APPLE_FM_REGION_SAVED:-0}
# Last request result for harnesses and debugging: pending, ok, empty, exit:N, unsafe (control characters, several lines, or an added destructive command), mismatch, timeout, stale, cancelled or no-cli.
typeset -g _APPLE_FM_LAST_OUTCOME=${_APPLE_FM_LAST_OUTCOME:-} _APPLE_FM_REQUEST_BEFORE=${_APPLE_FM_REQUEST_BEFORE:-}
typeset -ga _APPLE_FM_SAVED_REGION
# zsh does not set $! for <(...), so each bridge prints its own PID first and the caller reads it here.
_apple_fm_bridge_pid() { emulate -L zsh; local pid; IFS= read -r -u "$1" pid && [[ $pid == <-> ]] || pid=-1; typeset -g "$2=$pid"; }
# Counts commands that delete, overwrite or escalate: rm, sudo, doas, dd, shred, mkfs, recursive chmod, chown or chgrp,
# a forced git push, and redirects that truncate a file other than /dev/null. Sets REPLY, so the caller doesn't fork.
_apple_fm_risky_count() {
  emulate -L zsh -o extendedglob
  local -a words=(${(z)1}); local i w n=0
  for (( i = 1; i <= $#words; i++ )); do
    w=${words[i]}
    case $w in
      rm|sudo|doas|dd|shred|mkfs|mkfs.*) (( n++ ));;
      '>'|'>|'|'&>'|'&>|'|[0-9]'>'|[0-9]'>|') [[ ${words[i+1]-} == /dev/null ]] || (( n++ ));;
      chmod|chown|chgrp) [[ ${words[i+1]-} == (--recursive|-[[:alpha:]]#R[[:alpha:]]#) ]] && (( n++ ));;
      push) [[ ${words[i-1]-} == git && -n ${(M)words[i+1,-1]:#(-f|--force*|+*)} ]] && (( n++ ));;
    esac
  done
  REPLY=$n
}
_apple_fm_state() { emulate -L zsh; local sep=$'\x1f'; print -rn -- "${PWD}${sep}${LBUFFER}${sep}${RBUFFER}${sep}${CURSOR}"; }
_apple_fm_message() { emulate -L zsh; zle -M -- "$1" 2>/dev/null; }
_apple_fm_clear() {
  emulate -L zsh
  _APPLE_FM_SUGGESTION=''; POSTDISPLAY=''
  if (( _APPLE_FM_REGION_SAVED )); then region_highlight=("${_APPLE_FM_SAVED_REGION[@]}"); _APPLE_FM_REGION_SAVED=0; fi
  zle -R 2>/dev/null
}
_apple_fm_close_request() {
  emulate -L zsh
  if (( _APPLE_FM_FD >= 0 )); then zle -F "$_APPLE_FM_FD" 2>/dev/null; { exec {_APPLE_FM_FD}<&-; } 2>/dev/null; _APPLE_FM_FD=-1; fi
  # The bridge traps TERM and kills its direct fm child.
  if (( _APPLE_FM_PID > 0 )); then kill "$_APPLE_FM_PID" 2>/dev/null; wait "$_APPLE_FM_PID" 2>/dev/null; _APPLE_FM_PID=-1; fi
  [[ -n $_APPLE_FM_FILE ]] && rm -f -- "$_APPLE_FM_FILE"; _APPLE_FM_FILE=''
  [[ $1 == preserve ]] || _APPLE_FM_REQUEST_GEN=-1
}
_apple_fm_close_timer() {
  emulate -L zsh
  if (( _APPLE_FM_TIMER_FD >= 0 )); then zle -F "$_APPLE_FM_TIMER_FD" 2>/dev/null; { exec {_APPLE_FM_TIMER_FD}<&-; } 2>/dev/null; _APPLE_FM_TIMER_FD=-1; fi
  if (( _APPLE_FM_TIMER_PID > 0 )); then kill "$_APPLE_FM_TIMER_PID" 2>/dev/null; _APPLE_FM_TIMER_PID=-1; fi
}
_apple_fm_close_timeout() {
  emulate -L zsh
  if (( _APPLE_FM_TIMEOUT_FD >= 0 )); then zle -F "$_APPLE_FM_TIMEOUT_FD" 2>/dev/null; { exec {_APPLE_FM_TIMEOUT_FD}<&-; } 2>/dev/null; _APPLE_FM_TIMEOUT_FD=-1; fi
  if (( _APPLE_FM_TIMEOUT_PID > 0 )); then kill "$_APPLE_FM_TIMEOUT_PID" 2>/dev/null; _APPLE_FM_TIMEOUT_PID=-1; fi
}
_apple_fm_cancel() { emulate -L zsh; [[ $_APPLE_FM_LAST_OUTCOME == pending ]] && _APPLE_FM_LAST_OUTCOME=cancelled; (( ++_APPLE_FM_GENERATION )); _apple_fm_close_request; _apple_fm_close_timer; _apple_fm_close_timeout; _apple_fm_clear; }
_apple_fm_show() {
  emulate -L zsh
  (( _APPLE_FM_REGION_SAVED )) || { _APPLE_FM_SAVED_REGION=("${region_highlight[@]}"); _APPLE_FM_REGION_SAVED=1; }
  POSTDISPLAY=$_APPLE_FM_SUGGESTION
  region_highlight=("${_APPLE_FM_SAVED_REGION[@]}" "${#LBUFFER} $(( ${#LBUFFER} + ${#_APPLE_FM_SUGGESTION} )) fg=8")
  zle -R 2>/dev/null
}
_apple_fm_response() {
  emulate -L zsh
  local fd=$1 result_status response bytes state explicit
  IFS= read -r -u "$fd" result_status || result_status=125
  _apple_fm_close_timeout
  [[ -f $_APPLE_FM_FILE ]] || { _APPLE_FM_LAST_OUTCOME=stale; _apple_fm_close_request; return; }
  bytes=$(wc -c < "$_APPLE_FM_FILE"); state=$(_apple_fm_state); explicit=$_APPLE_FM_EXPLICIT
  if [[ $state != $_APPLE_FM_REQUEST_STATE || $_APPLE_FM_GENERATION -ne $_APPLE_FM_REQUEST_GEN || $state == $_APPLE_FM_DISMISSED ]]; then _APPLE_FM_LAST_OUTCOME=stale; _apple_fm_close_request; return; fi
  if (( bytes > 4096 )); then _APPLE_FM_LAST_OUTCOME=unsafe; _apple_fm_close_request; (( explicit )) && _apple_fm_message 'Apple FM returned an unsafe completion.'; return; fi
  response=$(<"$_APPLE_FM_FILE"); _apple_fm_close_request preserve
  [[ $result_status != 0 ]] && _APPLE_FM_LAST_OUTCOME=exit:$result_status || _APPLE_FM_LAST_OUTCOME=empty
  if [[ $result_status != 0 || -z $response ]]; then (( explicit )) && _apple_fm_message 'Apple FM is unavailable or returned no completion.'; return; fi
  [[ $response != *$'\n'* && $response != *$'\r'* && $response != *[$'\x00'-$'\x1f'$'\x7f']* ]] || { _APPLE_FM_LAST_OUTCOME=unsafe; (( explicit )) && _apple_fm_message 'Apple FM returned an unsafe completion.'; return; }
  # The model returns the whole line, so only a reply that starts with the typed text is shown, minus that text.
  [[ $response == "$_APPLE_FM_REQUEST_BEFORE"* ]] || { _APPLE_FM_LAST_OUTCOME=mismatch; (( explicit )) && _apple_fm_message 'Apple FM returned a different command line.'; return; }
  response=${response#"$_APPLE_FM_REQUEST_BEFORE"}
  [[ -n $response ]] || { _APPLE_FM_LAST_OUTCOME=empty; return; }
  # A suggestion may not add a destructive command the user hasn't typed; one they typed themselves still gets suggestions.
  local typed_risk REPLY; _apple_fm_risky_count "$_APPLE_FM_REQUEST_BEFORE"; typed_risk=$REPLY; _apple_fm_risky_count "$_APPLE_FM_REQUEST_BEFORE$response"
  (( REPLY > typed_risk )) && { _APPLE_FM_LAST_OUTCOME=unsafe; (( explicit )) && _apple_fm_message 'Apple FM suggested a destructive command, so it is not shown.'; return; }
  _APPLE_FM_LAST_OUTCOME=ok; _APPLE_FM_SUGGESTION=$response; _apple_fm_show
}
_apple_fm_timeout() {
  emulate -L zsh
  local fd=$1 generation explicit; IFS= read -r -u "$fd" generation || true
  [[ $generation == $_APPLE_FM_REQUEST_GEN ]] || return
  _APPLE_FM_LAST_OUTCOME=timeout; explicit=$_APPLE_FM_EXPLICIT; _apple_fm_close_request; _apple_fm_close_timeout
  (( explicit )) && _apple_fm_message "Apple FM timed out after ${APPLE_FM_TIMEOUT}s."
}
_apple_fm_request() {
  emulate -L zsh
  local explicit=$1 state=$2 before=$LBUFFER prompt instructions file fd timeout_fd
  (( _APPLE_FM_ENABLED )) || return
  [[ $CURSOR -eq ${#LBUFFER} && -z $RBUFFER && -n $LBUFFER ]] || { (( explicit )) && _apple_fm_message 'Apple FM suggestions require the cursor at the end of a nonempty line.'; return; }
  [[ -x $APPLE_FM_COMMAND ]] || { _APPLE_FM_LAST_OUTCOME=no-cli; (( explicit )) && _apple_fm_message "Apple FM CLI is unavailable: ${APPLE_FM_COMMAND}"; return; }
  _apple_fm_close_request; _apple_fm_close_timeout; _apple_fm_clear; _APPLE_FM_LAST_OUTCOME=pending
  (( ${#before} > APPLE_FM_CONTEXT_CAP )) && before=${before[-APPLE_FM_CONTEXT_CAP,-1]}
  instructions='Complete the zsh command line the user is typing. The last word may be cut off; finish it. Return the whole completed command line on one line, starting with exactly the text typed so far, without explanation or code fences.'
  prompt=$'Shell: zsh\nWorking directory: '${PWD}$'\nTyped so far:\n'${before}$'\n\nReturn the completed command line.'
  file=$(mktemp -t apple-fm-result.XXXXXX) || { _apple_fm_message 'Apple FM could not create its request result.'; return; }
  _APPLE_FM_FILE=$file; _APPLE_FM_REQUEST_BEFORE=$before; _APPLE_FM_REQUEST_STATE=$state; _APPLE_FM_REQUEST_GEN=$_APPLE_FM_GENERATION; _APPLE_FM_EXPLICIT=$explicit
  exec {fd}< <((print -r -- ${sysparams[pid]}; child=''; trap '[[ -n $child ]] && kill -KILL "$child" 2>/dev/null; wait "$child" 2>/dev/null; exit 143' HUP INT TERM; print -rn -- "$prompt" | "$APPLE_FM_COMMAND" respond --model system --no-stream --greedy --instructions "$instructions" >| "$file" 2>/dev/null & child=$!; wait "$child"; print -r -- $?))
  _APPLE_FM_FD=$fd; _apple_fm_bridge_pid $fd _APPLE_FM_PID; zle -F -w "$fd" _apple_fm_response
  exec {timeout_fd}< <(print -r -- ${sysparams[pid]}; integer ticks=$(( APPLE_FM_TIMEOUT * 100 )); zselect -t $ticks; print -r -- "$_APPLE_FM_REQUEST_GEN")
  _APPLE_FM_TIMEOUT_FD=$timeout_fd; _apple_fm_bridge_pid $timeout_fd _APPLE_FM_TIMEOUT_PID; zle -F -w "$timeout_fd" _apple_fm_timeout
}
_apple_fm_debounce() {
  emulate -L zsh
  local fd=$1 gen state; IFS= read -r -u "$fd" gen || true; _apple_fm_close_timer
  [[ $gen == $_APPLE_FM_GENERATION ]] || return; state=$(_apple_fm_state)
  [[ $state == $_APPLE_FM_DISMISSED ]] || _apple_fm_request 0 "$state"
}
_apple_fm_schedule() {
  emulate -L zsh
  local state=$1 fd
  [[ $state == $_APPLE_FM_DISMISSED || $CURSOR -ne ${#LBUFFER} || -n $RBUFFER || -z $LBUFFER ]] && return
  _apple_fm_close_timer; exec {fd}< <(print -r -- ${sysparams[pid]}; integer ticks=$(( APPLE_FM_DEBOUNCE * 100 )); zselect -t $ticks; print -r -- "$_APPLE_FM_GENERATION")
  _APPLE_FM_TIMER_FD=$fd; _apple_fm_bridge_pid $fd _APPLE_FM_TIMER_PID; zle -F -w "$fd" _apple_fm_debounce
}
_apple_fm_pre_redraw() {
  emulate -L zsh
  (( _APPLE_FM_ENABLED )) || return; local state=$(_apple_fm_state)
  if [[ $state != $_APPLE_FM_OBSERVED ]]; then _APPLE_FM_OBSERVED=$state; _apple_fm_cancel; _apple_fm_schedule "$state"; fi
}
_apple_fm_line_init() { emulate -L zsh; _APPLE_FM_OBSERVED=''; _APPLE_FM_DISMISSED=''; _apple_fm_cancel; }
_apple_fm_line_finish() { emulate -L zsh; _apple_fm_cancel; _APPLE_FM_OBSERVED=''; _APPLE_FM_DISMISSED=''; }
fm-suggest() { emulate -L zsh; local state=$(_apple_fm_state); _APPLE_FM_DISMISSED=''; _apple_fm_cancel; _APPLE_FM_OBSERVED=$state; _apple_fm_request 1 "$state"; }
_apple_fm_tab() {
  emulate -L zsh
  local state=$(_apple_fm_state)
  if [[ -n $_APPLE_FM_SUGGESTION && $state == $_APPLE_FM_REQUEST_STATE && $_APPLE_FM_GENERATION -eq $_APPLE_FM_REQUEST_GEN ]]; then LBUFFER+=${_APPLE_FM_SUGGESTION}; _apple_fm_clear; _APPLE_FM_OBSERVED=$(_apple_fm_state); return; fi
  [[ $KEYMAP == viins ]] && zle "${_APPLE_FM_TAB_VIINS:-expand-or-complete}" || zle "${_APPLE_FM_TAB_EMACS:-expand-or-complete}"
}
_apple_fm_escape() {
  emulate -L zsh
  _APPLE_FM_DISMISSED=$(_apple_fm_state); _apple_fm_cancel; _APPLE_FM_OBSERVED=$_APPLE_FM_DISMISSED
  [[ $KEYMAP == viins ]] && zle "${_APPLE_FM_ESC_VIINS:-undefined-key}" || zle "${_APPLE_FM_ESC_EMACS:-undefined-key}"
}
zle -N _apple_fm_response; zle -N _apple_fm_debounce; zle -N _apple_fm_timeout
zle -N fm-suggest; zle -N apple-fm-tab _apple_fm_tab; zle -N apple-fm-dismiss _apple_fm_escape
_apple_fm_binding() { emulate -L zsh; local b=$(bindkey -M "$1" "$2"); print -r -- "${${(z)b}[2]}"; }
apple-fm-enable() {
  emulate -L zsh
  (( _APPLE_FM_ENABLED )) && return
  _APPLE_FM_TAB_EMACS=$(_apple_fm_binding emacs '^I'); _APPLE_FM_TAB_VIINS=$(_apple_fm_binding viins '^I')
  _APPLE_FM_ESC_EMACS=$(_apple_fm_binding emacs '^['); _APPLE_FM_ESC_VIINS=$(_apple_fm_binding viins '^[')
  _APPLE_FM_TRIGGER_EMACS=$(_apple_fm_binding emacs "$APPLE_FM_TRIGGER"); _APPLE_FM_TRIGGER_VIINS=$(_apple_fm_binding viins "$APPLE_FM_TRIGGER")
  bindkey -M emacs '^I' apple-fm-tab; bindkey -M viins '^I' apple-fm-tab; bindkey -M emacs '^[' apple-fm-dismiss; bindkey -M viins '^[' apple-fm-dismiss
  bindkey -M emacs "$APPLE_FM_TRIGGER" fm-suggest; bindkey -M viins "$APPLE_FM_TRIGGER" fm-suggest
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget -d line-pre-redraw _apple_fm_pre_redraw 2>/dev/null; add-zle-hook-widget line-pre-redraw _apple_fm_pre_redraw
  add-zle-hook-widget -d line-init _apple_fm_line_init 2>/dev/null; add-zle-hook-widget line-init _apple_fm_line_init
  add-zle-hook-widget -d line-finish _apple_fm_line_finish 2>/dev/null; add-zle-hook-widget line-finish _apple_fm_line_finish
  _APPLE_FM_ENABLED=1; _APPLE_FM_OBSERVED=$(_apple_fm_state)
}
apple-fm-disable() {
  emulate -L zsh
  (( _APPLE_FM_ENABLED )) || return; _apple_fm_cancel; autoload -Uz add-zle-hook-widget
  add-zle-hook-widget -d line-pre-redraw _apple_fm_pre_redraw 2>/dev/null; add-zle-hook-widget -d line-init _apple_fm_line_init 2>/dev/null; add-zle-hook-widget -d line-finish _apple_fm_line_finish 2>/dev/null
  bindkey -M emacs '^I' "${_APPLE_FM_TAB_EMACS:-expand-or-complete}"; bindkey -M viins '^I' "${_APPLE_FM_TAB_VIINS:-expand-or-complete}"
  bindkey -M emacs '^[' "${_APPLE_FM_ESC_EMACS:-undefined-key}"; bindkey -M viins '^[' "${_APPLE_FM_ESC_VIINS:-undefined-key}"
  bindkey -M emacs "$APPLE_FM_TRIGGER" "${_APPLE_FM_TRIGGER_EMACS:-undefined-key}"; bindkey -M viins "$APPLE_FM_TRIGGER" "${_APPLE_FM_TRIGGER_VIINS:-undefined-key}"; _APPLE_FM_ENABLED=0
}
apple-fm-remove() { emulate -L zsh; apple-fm-disable; unfunction apple-fm-enable apple-fm-disable apple-fm-remove fm-suggest _apple_fm_* 2>/dev/null; }
