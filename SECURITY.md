# Security Policy

## Supported versions

Only the latest release gets security fixes. The download from GitHub checks for a new
release once a day and installs it with one click, and the Mac App Store version is
updated by the App Store, so a fix ships as a normal release.

## Reporting a vulnerability

Please don't open a public issue. Report it privately through
[this repository's security advisories](https://github.com/iAlborz/BentoStats/security/advisories/new).
Only you and the maintainer can see it.

Include the Bento Stats version, whether you have the download or the App Store version,
your macOS version, and steps to reproduce. You'll be credited in the release notes
unless you'd rather not be named.

## Scope

- The Bento Stats app and its source in this repository, both the download and the Mac App
  Store version
- The in-app updater: the daily check of this repository's latest release, and the check
  that the downloaded app is Bento Stats, newer, signed by the same team and notarized
  before it is installed
- The signed, notarized `BentoStats.dmg` and `BentoStats.zip` on GitHub Releases

Problems in [AirStats](https://github.com/byrencheema/airstats) itself, which Bento Stats
is based on, belong in its own repository.
