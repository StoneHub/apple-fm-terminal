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

## Packaging cleanup verified October 18, 2026

- Release archives suppress macOS AppleDouble generation and exclude existing
  `._*` and `.DS_Store` entries. Directory installs also filter these entries.
- Upgrades remove genuine AppleDouble sidecars only for package-owned paths;
  unrelated files and similarly named ordinary text files are preserved.
- `python3 tests/packaging.py` passed on macOS: real extended attributes,
  archive creation/extraction, dirty directory installs, upgrade cleanup,
  payload/inventory checks and unrelated-file preservation. Shell syntax passed.
- Existing installed metadata debris was removed and the installer updated;
  shell settings and running/model behavior were unchanged. No Swift rebuild
  was needed for this packaging-only change.
- Test when using the next package: install/update normally; no `._*` files
  should appear in the installed payload, and normal shell startup should work.

Cleanup: packaging tests remove their isolated homes, archives and staging
folders. No build/dist outputs, temporary processes or test installs retained.

## Self-contained preview candidate - October 18, 2026

Version 0.3.0-preview.1. Public publication remains on hold. The staged public
package uses the published AppleFM revision; private local overlays are excluded.

- Private CPython 3.12.15 runtime (python-build-standalone 20261013, arm64)
  bundled with checksum-pinned provenance and dependency licenses. No user-side
  Xcode, developer tools or separate Python install is required. Runtime is
  isolated from Python environment/user packages, with bytecode writes disabled.
- macOS 26+, native Apple Silicon and model readiness checked before activation.
  Users launch Install.command from the disk image/folder, complete the existing
  wizard, and open a normal zsh tab. Managed settings and Tab/Enter stay separate.
- Build/13 focused shell checks and metadata packaging regression passed. Exact
  archive tested with external Python/Swift/Xcode commands deliberately failing,
  poisoned Python environment, native model generation, actual shell-buffer
  insertion before Enter, idempotent update and full runtime removal. Original
  shell bytes and unrelated files preserved. PTY proof is not physical GUI proof.
- Added explicit-identity Mach-O signing, disk image signing, notarytool submit,
  acceptance/stapling/assessment and checksum generation. No certificate is chosen
  automatically. No GitHub release, tag or asset upload occurs in preparation.
- Local tar/disk image candidates prepared (approximately 22/29 MB; payload 58 MB).

Remaining gates: maintainer's Developer ID Application identity and notarytool
profile, accepted/stapled notarization, quarantine/Terminal.app installation on a
second supported Mac without developer tools (including intended macOS 26 minimum),
and actual SSH/custom-shell trial. Publication requires separate authorization.
See docs/preview-release.md for the exact procedure and draft release notes.

Cleanup owner: Terminal task. Remove build/compiler/download/staging/test outputs
after final readback. Keep only final dist/ candidates/checksums for Monroe's
review until replaced or publication is cancelled. No temporary test runtime or
service should survive this task.
