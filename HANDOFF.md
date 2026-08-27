# Vigilant — Project Handoff

You're picking up a project mid-stream. This file is the full state so a new
session (e.g. running on the Mac Mini) can continue.

## What Vigilant is

A two-app system that keeps a Mac Mini "active" on a work schedule (replacing an
old Python mouse-jiggler), controllable from an iPhone **without a VPN**. The Mac
runs the agent; the phone flips it on/off and monitors it. Sync is via a
**private CloudKit database + silent push** — no server, no VPN.

**The Mac Mini is the target machine.** It's the machine that must actually run
the macOS app and appear active. Development happened on a MacBook Pro; the goal
now is to deploy and run on the Mini.

## Repo

- GitHub: `https://github.com/mgcather07/Vigilant_iOS.git` (public).
- Everything is committed and pushed; working tree was clean at handoff.
- The repo lives on an external SSD on the Mini. Find it with
  `mdfind -name project.yml` or look under `/Volumes/...`. Clone it if it's not
  checked out here yet.
- Git identity: Michael Cather / mgcather07@gmail.com. `gh` CLI authed as
  `mgcather07`.

## Tech stack

- Two targets: `Vigilant` (macOS) and `VigilantRemote` (iOS), plus a `Shared/`
  folder used by both.
- **XcodeGen**: the `.xcodeproj` is generated from `project.yml`. To change
  targets/settings, edit `project.yml`, then run `xcodegen generate`.
- Team ID `9LU8N76A9C`; CloudKit container `iCloud.io.vigilant.co.Vigilant`
  (verify in the `.entitlements` files).

## What's built so far

- macOS app is BOTH a menu-bar agent (eye icon) AND a normal windowed app (Dock
  icon). Sidebar (`NavigationSplitView`): **Overview, Monitor, Schedule,
  Holidays**.
- Core function: mouse jiggle via HID events + a power assertion to defeat
  idle/away timers — `VigilantMac/JiggleEngine.swift`.
- **Monitoring**: `VigilantMac/SystemMetrics.swift` samples
  CPU/memory/disk/network/load/processes/device via Darwin APIs ->
  `Shared/SystemSnapshot.swift` -> shared cards in `Shared/MetricCards.swift`.
  The Monitor tab shows 7 uniform cards; the snapshot rides along in the CloudKit
  heartbeat so the iPhone sees the same data.
- **Schedule** (`VigilantMac/ScheduleView.swift`) and **Holidays**
  (`VigilantMac/HolidaysView.swift`) are editable and persisted
  (`VigilantMac/VigilantSettings.swift`, UserDefaults). They drive the real
  decision logic in `VigilantMac/AppController.swift`. Holiday/work-schedule
  logic (ported from the original Python) lives in
  `Shared/BusinessCalendar.swift` + `Shared/WorkSchedule.swift`.
- iOS app (`VigilantRemote/`): big On/Off switch, schedule toggle, status, and
  the monitoring cards from the synced snapshot.
- **Local/offline mode**: launching with env var `VIGILANT_LOCAL=1` runs the app
  WITHOUT CloudKit, so unsigned dev builds don't crash on `CKContainer`. Shipping
  builds leave it unset. Dev convenience only.

## How we've been building (dev, unsigned)

```bash
xcodegen generate
# macOS
xcodebuild -project Vigilant.xcodeproj -scheme Vigilant \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
# ran with:
VIGILANT_LOCAL=1 /path/to/Vigilant.app/Contents/MacOS/Vigilant &
```

## What's NOT done — the work on the Mini

1. **Real signed build so sync works.** Open the project in Xcode on the Mini,
   sign both targets with the Apple ID (automatic signing), and confirm both have
   the **iCloud/CloudKit** capability pointing at the SAME container
   `iCloud.io.vigilant.co.Vigilant` plus **Push Notifications** / background
   silent push. Build & Run `Vigilant` (macOS) here — NOT in local mode (do not
   set `VIGILANT_LOCAL`).
2. **Grant Accessibility** to Vigilant (System Settings ▸ Privacy & Security ▸
   Accessibility) so the jiggle can move the cursor.
3. **Add to Login Items** so it survives reboots.
4. Build/run `VigilantRemote` on the iPhone (or TestFlight later); confirm the
   phone toggles the Mini and shows live metrics.

**Deployment decision (was left open):** recommended path is the above — build on
the Mini with Xcode automatic signing (development CloudKit environment matches
current entitlements). Alternative (to avoid installing Xcode) was Developer ID +
notarize with production CloudKit, but Xcode-on-Mini is simpler.

## Backlog / ideas discussed

- Phone-editable schedule & holidays (currently editable only on the Mac).
- Threshold **alerts + push** (e.g. "disk 95% full" to the phone) — good fit for
  the existing push plumbing.

## Git workflow

Commit + push each change to `main`. End commit messages with a
`Co-Authored-By: Claude` trailer.

## First steps here

Locate the repo on the SSD, confirm Xcode is installed (`xcodebuild -version`),
then open the project and get a **signed** build running on this Mini.
