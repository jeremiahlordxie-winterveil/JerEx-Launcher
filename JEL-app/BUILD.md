# JEL build and release handoff

1. Install the .NET 8 SDK and Inno Setup 6.
2. Run `dotnet build JEL.sln` for a fast source check.
3. Run `build-release.ps1 -Version 0.1.0` to publish self-contained win-x64, compile the per-user installer, create the ZIP, and write SHA-256 files.

The release ZIP is assembled from `artifacts/package` and contains only the
installer and release documents. User `.env`, `.codex`, logs and local caches
are never copied into it.
