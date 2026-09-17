# Apple FM zsh autocomplete

This is a small zle plugin for macOS 27. It asks the on-device Apple model for a single-line suffix, renders that suffix after the prompt, and inserts it into `LBUFFER` only when Tab is pressed. Enter remains the separate execution action.

## Try it

```zsh
source /Users/monroe/Developer/GitRepos/FM/terminal/apple-fm.zsh
apple-fm-enable
```

Type a command prefix at the end of an otherwise empty line and pause for the default 350 ms, or invoke the explicit request with `Ctrl-X Ctrl-F` (`$APPLE_FM_TRIGGER`). Press Tab to insert a visible suffix. Escape dismisses it. `apple-fm-disable` restores the Tab and Escape bindings captured when enabled; `apple-fm-remove` disables and removes the plugin functions. No `.zshrc` is edited.

The CLI path is controlled by `$APPLE_FM_COMMAND` and defaults to `/usr/bin/fm`. Requests use stdin plus `respond --model system --no-stream --greedy`; prompts, history, and completions are not persisted. Set `APPLE_FM_DEBOUNCE` before enabling to change the delay.

The first version handles one line with the cursor at the end. It rejects multiline/control-character output, drops responses for changed buffers or directories, keeps only one active request and timer, and does not invoke generated text. Existing autosuggestion plugins remain responsible for their own display; if they also bind the same keys, load/order should be checked in the user's shell.
