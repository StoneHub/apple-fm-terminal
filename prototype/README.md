# Terminal Ask prototype

Question: does a standalone, on-device helper become useful when it can see a
small amount of the current shell session, answer an explicit question, and
offer one command for review before insertion and separate execution?

This is a disposable functional experiment, not a release or an addition to the
installed autocomplete plugin. Jot is not required. No installation, startup-file
edit, network configuration change, or persistent service is involved.

## Try it

Requires a supported Mac with `/usr/bin/fm`, Apple Intelligence available, and
Python 3. From Terminal, run the single launcher command:

```sh
/Users/monroe/Developer/GitRepos/FM/terminal/prototype/terminal-help
```

Or, from another checkout, run `./prototype/terminal-help`. It opens a separate
zsh session with a visible **FM Ask** prompt. Your original shell configuration
and bindings are not loaded into the disposable shell. `exit` returns to your
original shell. To use it over SSH, run the launcher on the supported remote Mac;
inference and context stay on that Mac. SSH transport has not been exercised.

Inside the session:

```text
ask "Why did the last command fail?"
ask "How do I list attached disks?"
ask
ask --context
ask --clear
ask --help
```

- **Ctrl-X then ?** asks about the last command when the buffer is empty, or
  uses the text currently in your buffer as the question. It preserves that
  buffer until you accept or edit it.
- **Tab** replaces the unchanged buffer with the proposed command. **Enter**
  remains the separate execution action. Pressing Enter before Tab does not
  execute the preview.
- **Escape**, editing the buffer, or changing directories dismisses a preview.
- **Typing or Ctrl-C while thinking** cancels the request. Typeahead cannot
  accept a command the model has not finished showing.
- A simple, directly entered missing command gets a short reminder of the help
  shortcut. The normal `command not found` error and exit status remain. The
  reminder itself does not invoke the model.

## What context means here

The launcher relays a private PTY and the shell marks command boundaries. Only
output between those boundaries is retained. There is no scrollback scraping,
history import, screen capture, microphone capture, cloud fallback or prompt log.

The in-memory ring holds at most five completed top-level commands, their working
directories and exit statuses, and up to 1,800 characters of output per command
(backed by at most 2,400 bytes). Requests trim the newest records to a 7,000-character
JSON budget. Control sequences are removed before context reaches the model.
Script output can appear as output of the top-level script invocation, but the
script's internal commands are not hooked. Any output printed during a command
may be included; this is not a secret detector. Use a disposable session for the
trial and `ask --context` to inspect what will be included.

Help responses, previews and help-control commands are excluded, so model guesses
do not feed themselves back as observed evidence. An accepted command becomes
evidence only after you execute it. `ask --clear` forgets the ring; exiting drops
the session. A mode-0700 temporary directory contains only the scratch shell rc,
response schema and mode-0600 local socket; it is removed on exit. Context and
model responses are not saved there. Abrupt SIGKILL or a machine crash can leave
that configuration-only directory behind.

## Scripts and compatibility

The prototype does not wrap commands, redirect their descriptors, install an
error trap, or redefine `command_not_found_handler`. Prompt hooks use builtins to
mark top-level command boundaries; the model runs only for an explicit request.
The ring is bounded and command capture does not invoke Python per command.

`ask` is a non-exported function scoped to this interactive shell. It refuses
calls from functions, sourced scripts, loops, substitutions, pipelines, redirected
input/output and pasted command blocks. A missing command inside a known script,
function, pipeline or loop does not show a help reminder. The launcher refuses
noninteractive/piped use. Automation launched from this shell runs normally;
shell commands intentionally asking whether `ask` is defined will, of course,
see that interactive function. The private `--client` switch is internal IPC,
not a security boundary against other processes owned by the same user.

This initial shell is deliberately isolated from the existing suffix plugin and
other shell customizations. Ordinary command completion works when no proposal
is ready. Normal terminal resizing and child job control use the PTY. Full-screen
programs and other plugins need a separate compatibility trial before a release.

## Model limits

Requests use `fm respond --model system` with structured output and a 25-second
deadline. There is no inference when commands succeed, fail, or sit idle unless
you explicitly ask. The helper checks executable availability, rejects unchanged
failed commands, validates `sw_vers` arguments, and rejects control characters and
shell operators. Known privilege-escalation/file-removal/destructive disk command
names are withheld from insertion. These checks do not prove an arbitrary
command's flags, effects or correctness; review the explanation and command.

The model can answer without proposing a command. It may also give a poor
explanation or fail to offer a useful next step. Native PTY checks are separate
from Monroe's actual Terminal.app acceptance.

## Checks and trial verdict

```sh
PYTHONDONTWRITEBYTECODE=1 python3 prototype/check.py
```

The focused PTY checks cover context provenance/bounds/clearing, typed and shortcut
requests, Tab then Enter, dismissal after edits, missing-command status, script
and function isolation, invalid proposals, cancellation, and early typeahead.
Fixtures invoke no real model and write only synthetic evidence under their own
automatically removed temporary directories.

Real-model trial on this Mac: after `sw_vers -product` failed, the helper used the
actual usage output to propose `sw_vers --productVersion`; Tab inserted it and a
later Enter returned the version. An earlier schema with a generic `command`
field repeated the failed command despite explaining the correction. The
`next_command` field and rejection check fixed that observed case, not all model
quality problems.

The first `diskpart` shortcut trial correctly explained that the command is not
available on macOS, but proposed the unrelated `ls -la`. The prompt now includes
tool purposes, an explicit diskutil hint and a clarification/abstention rule. A
later real-model shortcut trial proposed `diskutil list`; it was dismissed without
execution. The specific unrelated file-listing proposal is also withheld when
reviewing that last failure. These observed failures are why the prototype's
usefulness still needs a real trial.

Test when you sit down: run the launcher, try a missing command, request help
using both entry points, inspect `ask --context`, accept with Tab, and pause before
Enter. Try a script with an error: it should retain its normal behavior and never
start the model. Then `exit` and confirm your original shell is unchanged.

Owner: this chat. Retain branch `prototype/terminal-ask-session` and these source
files for Monroe's trial. No temporary test session or model process should
remain after development checks. The removal/integration decision comes after
the trial answers the product question; the prototype stays out of `main` until
then. No public release or startup-file installation is part of this experiment.

Development checkpoint, October 17, 2026: seven PTY checks passed; the expanded
context-bound check and observed-failure validation check also passed after their
final changes. All development sessions/model processes were stopped and generated
scratch/test directories removed. Only the runnable source prototype is retained.
