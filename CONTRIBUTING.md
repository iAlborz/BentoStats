# Contributing

Bento Stats has a few opinions. They are here so a pull request does not have to find
them in review.

## Getting set up

You need macOS 14 or later and Xcode 16 or later.

```sh
git clone https://github.com/iAlborz/BentoStats.git
cd BentoStats
swift build
swift test
Scripts/build.sh          # debug .app bundle
Scripts/build.sh release  # optimised .app bundle
```

The script prints the path of the app it built. To run it, quit the copy that is running
(Quit in the panel, not `kill`, which skips saving the day's history), then open the new
one.

## Before you open a pull request

Run these:

```sh
swift build
swift test
.build/debug/AirStats --probe            # sanity check the collectors on your Mac
.build/debug/AirStats --render           # PNGs of every surface, in ./render
```

If you touched anything that draws, attach the relevant render. If you touched a
collector, say what you diffed its output against.

`--probe` prints raw collector output, so you can check it against `top`, `vm_stat`,
`netstat -ib`, `ioreg` and `pmset`. `--render` draws the menu bar, the panel and Settings
from fixture data at both appearances and both backing scales. Neither needs a screen.
`NSVisualEffectView` renders nothing offscreen, though, so a render shows layout and
SwiftUI drawing only: materials and translucency can only be judged on screen.

The fan minimum-RPM contract test can fail for a second while a fan spins down, so
re-run before you investigate. `swift build` sometimes reports success while linking
stale objects, so if an edit does not reach the binary, delete `.build` and build
again.

## House rules

**Never show a number the machine did not report.** A missing sensor renders as a dash
and an unsupported metric is greyed out with the reason attached. Never substitute a
zero, a guess or a last-known value. A sparkline with fewer than two samples draws
nothing, since a flat line reads as a metric pinned at zero.

**Keep both versions working.** The download and the Mac App Store version are built from
the same code. The App Store one runs in the App Sandbox, which cannot read temperatures or
fan speeds and must never update itself; `Capabilities.readsSensors` and
`UpdateFeed.url` are where the code tells the two apart. `AIRSTAT_NO_SENSORS=1` runs or
renders the App Store version's panel outside the sandbox, so check a change to a card
both ways.

**Comments explain why, not what.** A comment earns its place by recording the
measurement, the platform bug or the rejected alternative behind the code. If you removed
a comment's reason, remove the comment.

**Keep AirStatKit free of UI.** It imports Foundation, IOKit and the rest of the system,
never SwiftUI or AppKit. The tests and `--probe` run in a windowless process. (The
targets keep the names they had in AirStats, the app Bento Stats is based on.)

**Match the design system.** Spacing, type and colour come from `Design` in
`Sources/AirStatUI/Design/DesignSystem.swift`. Add a token there rather than a literal at
the call site.

## Commits

One change per commit. A subject that says what changed, for someone who uses the app,
and the reason in the body:

```
Accessory batteries from the IORegistry, not a private IOKit call
Without sensors: renders match the App Store copy, MacBook fans unlabelled
README: Bento Stats' own page
```

## Reporting a bug

Open an [issue](https://github.com/iAlborz/BentoStats/issues) with your Mac model, your
macOS version, whether you have the download or the App Store version, and the output of
the probe for the metric that misbehaved:

```sh
"/Applications/Bento Stats.app/Contents/MacOS/AirStats" --probe
```

Sensor coverage varies across Macs more than anything else here, so that output is often
the whole report. Security problems go to [SECURITY.md](SECURITY.md) instead.
