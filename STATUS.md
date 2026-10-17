# Terminal Ask 0.2.0 local preview

Outcome: integrate explicit help into normal zsh, using the existing AppleFM Swift
library. The install wizard owns setup/removal; Tab insertion and Enter execution
remain separate. Tracking: https://github.com/StoneHub/apple-fm-terminal/issues/16.

AppleFM is pinned to published revision 5b937241b0236f892af28588e75a78dd557acf21.
The compiled helper owns native generation; Python retains the proven PTY/context
transport for this slice. No shared-library source changes are required.

The normal-shell setup uses guarded .zshenv/.zshrc blocks so user initialization
runs once. Shell settings/history are preserved; emacs/vi bindings are captured
and restored, and an existing ask command is not replaced. Context pause/clear,
nested-shell exclusions, cancellation, bounded retention and script isolation
are part of the checked contract.

Task ownership: this chat owns build/, dist/, temporary PTYs/test homes and the
local installation. Build and package staging are disposable after installation
and verification. Keep installed files and private setup backups for use/removal;
keep the historical prototype source branch as the original experiment. No
persistent service or unrelated process is to be stopped for this task.

Finish line: focused checks, native generation, setup through the actual wizard,
installed binary readback, new normal-shell acceptance, source on main remotely,
and an updated issue. Public release/package-manager publication is not requested.

## Verified October 17, 2026

- Release build linked the pinned AppleFM Swift library. Native availability is
  `available`; no `/usr/bin/fm` call is used.
- 13 focused checks passed: normal startup once, aliases/options, custom vi Tab,
  existing ask preservation, cancellation/typeahead, scripts, context bounds,
  pause/resume, nested-shell isolation, idempotent wizard, symlinks, malformed
  block refusal and uninstall preservation.
- The checksum-verified local archive was installed through the actual wizard.
  Original .zshenv/.zshrc content outside managed blocks compared byte-for-byte.
- Installed model-helper SHA-256 equals the built payload:
  ba8d98ac436b33703fb1267d5e703fd819dfbb808d91f05e4eb689a2f2a970f0.
- A new normal login PTY using Monroe's real settings loaded help and kept the
  normal prompt. Native generation corrected the captured sw_vers error. Tab
  inserted the command with no execution; a separate Enter returned the version.
  This establishes installed PTY behavior, not a physical Terminal.app key trial.
- Existing user windows/prototype processes were not stopped. Open a new tab to
  use the installed setup. Physical Terminal.app polish, other shell plugins,
  full-screen compatibility and an actual SSH host remain dogfood checks.

Cleanup disposition: stop all task-created sessions and remove task-owned build/,
dist/, test directories and Python cache files after the installed readback. Keep
only source, the installed payload/private setup backups, and the historical
prototype branch. Public release and Homebrew publication remain separate.
