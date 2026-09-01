# Development verification

- .NET 8 SDK: installed and detected (`8.0.422`).
- `dotnet build JEL.sln`: passed with 0 warnings and 0 errors.
- Self-contained `win-x64` publish: passed.
- Inno Setup per-user script compile: passed.
- ZIP contents: verified to contain only the installer, SHA256SUMS.txt, README.txt, LICENSE.txt, CHANGELOG.txt and SECURITY.txt.
- Installer and ZIP SHA-256: generated and verified.
- Current-machine diagnostic: passed. It found `OpenAI.Codex 26.707.3748.0`, selected HTTP `127.0.0.1:7897`, and accepted OpenAI `401` plus ChatGPT `403` as reachable responses.
- Silent install, installed-app diagnostic and silent uninstall: passed. The existing ChatGPT `.env` SHA-256 was unchanged.

The normal launch path was intentionally not run because it can prompt to
change the current ChatGPT configuration or restart a running session. Manual
acceptance still needs a clean Windows user profile, no-proxy and bad-proxy
cases, upgrade behavior, and explicit confirmation/rejection tests.
