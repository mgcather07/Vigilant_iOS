# Vigilant

Keep your Mac Mini "active" on a schedule, and flip it on/off from your iPhone
**without a VPN** — the way a Reolink/Lorex camera reaches you from anywhere.

It replaces the daily `pyautogui` mouse-mover script with two native apps that
talk through your private iCloud database.

## How it works

```
 iPhone (Vigilant Remote)  ──write "enabled"──►  ☁️ CloudKit (your private DB)
                                                        │  silent push + polling
 Mac Mini (Vigilant)  ◄──read state, write heartbeat──┘
        │
        └─ jiggles the mouse with real HID events (resets idle/away timers)
           + holds a power assertion so the Mac doesn't idle-sleep
```

- Both devices only make **outbound** connections to iCloud, so there's nothing
  to port-forward and no VPN. This is exactly how consumer cameras do it.
- One shared CloudKit record (`controlState`) holds the on/off switch, the
  "follow work schedule" flag, and the Mac's live status/heartbeat.
- The phone flips the switch; the Mac reacts within a second or two via silent
  push, and every ~30s as a polling fallback.

## Targets

| Target            | Platform | Bundle ID                        | Notes |
|-------------------|----------|----------------------------------|-------|
| `Vigilant`        | macOS    | `io.vigilant.co.Vigilant`        | Menu-bar agent (no Dock icon). Runs on the Mac Mini. |
| `VigilantRemote`  | iOS      | `io.vigilant.co.VigilantRemote`  | The iPhone app with the big switch. |

Both share the code in `Shared/` and the **same** CloudKit container
`iCloud.io.vigilant.co.Vigilant`.

## Project generation

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen   # once
xcodegen generate       # regenerates Vigilant.xcodeproj after editing project.yml
```

Edit source and `project.yml`, not the `.xcodeproj` directly.

## First-time setup in Xcode (required — needs your Apple ID)

These steps register the iCloud container and push profile on your developer
account, which can only be done signed in to Xcode.

1. Open `Vigilant.xcodeproj`.
2. **Xcode ▸ Settings ▸ Accounts** → make sure your Apple ID (Team `9LU8N76A9C`)
   is signed in.
3. Select the **Vigilant** (macOS) target ▸ **Signing & Capabilities**:
   - Confirm "Automatically manage signing" + your Team.
   - The **iCloud** capability should already be present (from the entitlements
     file). Ensure **CloudKit** is checked and the container
     `iCloud.io.vigilant.co.Vigilant` is checked. If it doesn't exist yet, click
     **+** and let Xcode create it.
   - Confirm the **Push Notifications** capability is present.
4. Select the **VigilantRemote** (iOS) target ▸ **Signing & Capabilities**:
   - Same Team + automatic signing.
   - **iCloud ▸ CloudKit**, and check the **same** container
     `iCloud.io.vigilant.co.Vigilant` (not the per-app default). This is what
     lets the two apps see each other's data.
   - Confirm **Push Notifications** is present.
5. Build each target once so Xcode provisions everything.

## Running it

### Mac Mini (Vigilant)
1. Build & run the `Vigilant` scheme on the Mac Mini. An eye icon appears in the
   menu bar — there is no Dock icon or window.
2. The first time it tries to move the mouse, macOS will need **Accessibility**
   permission: **System Settings ▸ Privacy & Security ▸ Accessibility** → enable
   **Vigilant**. (The menu shows a "Grant access…" button too.)
3. To keep it running after reboots: **System Settings ▸ General ▸ Login Items**
   → add Vigilant. (This app is what your daily Calendar automation used to do —
   you can retire the Python script.)

### iPhone (Vigilant Remote)
1. Build & run the `VigilantRemote` scheme on your iPhone (same Apple ID as the
   Mac Mini — that's what shares the private database).
2. Flip the switch. The Mac reacts within a couple seconds.

## The switches

- **Enabled** — master on/off. When on with *Follow work schedule* off, the Mac
  stays active continuously.
- **Follow work schedule** — when on, the Mac only stays active during your
  Mon–Fri work windows and skips company holidays. The windows and holiday
  policy are ported from your Python script and live in
  `Shared/WorkSchedule.swift` and `Shared/BusinessCalendar.swift`.

## System monitoring

Vigilant also monitors the Mac Mini like a server dashboard. The Mac samples
its own health every few seconds and shows it in the window; the same snapshot
rides along in the CloudKit heartbeat so the **iPhone can watch the server
remotely**.

Cards (v1): **Processor Load** (user/system %), **Memory** (used %, active/
wired/compressed, swap), **Disk** (used/total for the boot volume), **Network**
(live up/down throughput), and **Device** (model, macOS version, host, uptime).

- Collection is macOS-only (`VigilantMac/SystemMetrics.swift`, Darwin/Mach APIs).
- The snapshot model + card UI are shared (`Shared/SystemSnapshot.swift`,
  `Shared/MetricCards.swift`), so both apps render identical widgets.
- Not yet (easy follow-ups): history graphs/sparklines, network *daily* totals
  (needs a small persistence layer — v1 shows live throughput), per-core CPU,
  temperature/fans, and threshold alerts/push when something spikes.

## Notes & limitations

- The macOS app is intentionally **not sandboxed** — posting synthetic HID mouse
  events (to reset idle/away timers) requires Accessibility, which is
  incompatible with the App Sandbox.
- `aps-environment` is `development`, which is correct for personal dev-signed
  builds. Switch to `production` only if you distribute via TestFlight/App Store.
- Good Friday dates are listed manually through 2028 in `BusinessCalendar.swift`
  (Easter isn't a fixed formula); add more years there as needed.
