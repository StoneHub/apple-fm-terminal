# Apple FM Terminal 0.3.0-preview.1

Ask Apple's on-device model for help in your normal zsh session. No separate
Python install, Xcode, Jot or API account is required. This preview includes its
own private runtime and a setup wizard that preserves existing shell settings.

Use ask or Ctrl-X then ?. Review the explanation and proposed command; Tab
inserts it, and a separate Enter executes it. Normal completion remains available.
Scripts never trigger help. Recent bounded session context stays in memory.

Requires a native Apple Silicon Mac running macOS 26 or later with Apple
Intelligence enabled and its model downloaded. Download the disk image, open
Install.command, complete the wizard and open a new Terminal tab.

Use apple-fm-terminal doctor for status, disable to remove the shell integration,
and uninstall to remove the installed package. There is no login item or permanent
model service. Settings backups are private; package updates exclude macOS
metadata debris. Model proposals still need review for correctness.

Preview limitations: zsh only; no guarantee of compatibility with every prompt or
completion plugin. Remote use requires installation and model readiness on the
remote Mac. No automatic execution, cloud fallback or unattended error fixing.
