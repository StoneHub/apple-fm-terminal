# Downloadable preview release preparation

Owner: Terminal maintainer. Version: 0.3.0-preview.1. Publication remains on hold.
No release/tag/assets are created by the preparation scripts.

## Candidate contents and ownership

The regular zsh experience, bounded in-memory context and Tab-then-Enter contract
remain the product. Install.command starts the existing wizard in Terminal.
A private relocatable CPython 3.12.15 runtime replaces the external Python
requirement. The bundled runtime never modifies system Python or PATH. It is
isolated from PYTHONHOME/PYTHONPATH and user site packages; Python runs with -I -B
so sessions and management do not create bytecode caches in the installation.
Users need macOS 26+, native Apple Silicon, zsh and Apple Intelligence ready.
Public inference uses the published AppleFM library revision in Package.resolved.
Private local overlays must not be included in release staging.

Runtime downloads are pinned by version, platform and SHA256 in
scripts/bundle-runtime.py. The full upstream archive supplies dependency license
texts and PYTHON.json; only the install runtime and license/provenance files ship.
Upstream source: https://github.com/astral-sh/python-build-standalone/releases/tag/20261013
Upstream documentation: https://gregoryszorc.com/docs/python-build-standalone/main/running.html

## Prepare and validate locally

Run ./scripts/prepare-preview.sh on the native Apple Silicon build Mac. It builds
the Swift helper, stages the runtime, creates the archives, creates a disk image,
and writes SHA256SUMS. Without signing credentials these are local candidates,
not approved distribution artifacts. Do not bypass Gatekeeper for a public build.

Run python3 -B tests/packaging.py, the 13 tests/check.py checks, and then
python3 -B tests/preview.py against the exact candidate. The archive test uses an
isolated HOME, blocks external Python/Swift/Xcode commands, poisons PYTHONHOME and
PYTHONPATH, installs via the interactive wizard, checks idempotent update, runs
native generation in an ordinary login PTY, inspects the actual accepted shell
buffer before Enter, executes separately, and removes the package while
preserving original configuration and unrelated files. No physical Terminal.app
or clean second-Mac acceptance is implied by a PTY check.

Before upload, use another supported Mac without developer tools: open the
quarantined downloaded disk image, open Install.command, complete the wizard,
open a normal Terminal tab, ask for help, Tab to insert, Enter to execute, close
the window, update and uninstall. Include a customized shell and an actual SSH
session to the supported remote Mac. Report these trials separately.

## Distribution signing and notarization

Use only the maintainer's intended Developer ID Application identity and matching
team. The scripts deliberately do not choose certificates automatically. An
Apple Development identity is insufficient for this distribution gate; another
person's available Developer ID must not be used.

Set APPLE_FM_SIGN_IDENTITY to the full intended Developer ID Application identity,
APPLE_FM_SIGN_TEAM to its team identifier, and APPLE_FM_NOTARY_PROFILE to a
previously configured notarytool keychain profile. Then rerun
./scripts/prepare-preview.sh. It signs each Mach-O executable/library in the
payload with hardened runtime and a timestamp before archiving; signs the disk
image; submits the disk image to Apple's notarization service; requires Accepted;
staples/validates the ticket; assesses the disk image; and regenerates checksums.
No credentials are recorded in the repository. Notarization uploads to Apple only
when APPLE_FM_NOTARY_PROFILE is explicitly supplied.

The notarized/stapled disk image is the intended easy-download format. The tar
archive contains the signed payload but cannot carry a stapled disk-image ticket;
validate its separate quarantine behavior before advertising it as an equivalent
consumer install path. Do not treat successful local ad-hoc execution as that
validation. The scripts themselves do not publish anything.

## Publish only after authorization

Confirm signing/notarization acceptance, fresh-Mac results and exact final
checksums; obtain publication authorization. Create GitHub prerelease
v0.3.0-preview.1 and upload the reviewed disk image, versioned archive, stable
archive alias, install.sh and SHA256SUMS. Read back the release and downloads.
The installer pins this preview tag so it cannot fall back to the legacy latest
release. Update README status when the release really exists. Homebrew remains
separate work. No CI runner is required for these local checks.

## Cleanup and retention

The Terminal task owns build/ and dist/. Remove disposable compiler products,
download archives, staging folders and logs after final verification. Retain the
compact final candidate files/checksums under dist/ for Monroe's review until
they are replaced or publication is explicitly cancelled. Tests own and remove
their temporary homes, copies and processes. No test server or login service
should remain running. Record the exact validation result and pending release
gates in STATUS.md and the preview issue before stopping.
