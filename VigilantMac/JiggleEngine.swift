//
//  JiggleEngine.swift
//  Vigilant (macOS)
//
//  The business end: nudges the mouse with real HID events so idle/away
//  timers (Teams, Slack, screen saver, etc.) stay reset, and holds an
//  IOKit power assertion so the Mac doesn't idle-sleep while active.
//
//  Posting HID events requires Accessibility permission, so this app is
//  intentionally NOT sandboxed.
//

import Foundation
import CoreGraphics
import ApplicationServices
import IOKit.pwr_mgt

@MainActor
final class JiggleEngine {

    private(set) var lastActivity: Date?
    private var assertionID: IOPMAssertionID = 0
    private var holdingAssertion = false

    /// Whether the process is trusted to post input events.
    var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant Accessibility (shows the system dialog once).
    func requestAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Move the cursor a hair and back using HID-level events.
    func jiggle() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let current = currentMouseLocation(source: source)

        let nudged = CGPoint(x: current.x + 1, y: current.y)
        postMove(to: nudged, source: source)
        postMove(to: current, source: source)

        lastActivity = Date()
    }

    private func currentMouseLocation(source: CGEventSource) -> CGPoint {
        // CGEvent(source:) with a nil-ish event returns current cursor location.
        if let probe = CGEvent(source: source) {
            return probe.location
        }
        return .zero
    }

    private func postMove(to point: CGPoint, source: CGEventSource) {
        guard let move = CGEvent(mouseEventSource: source,
                                 mouseType: .mouseMoved,
                                 mouseCursorPosition: point,
                                 mouseButton: .left) else { return }
        move.post(tap: .cghidEventTap)
    }

    // MARK: - Power assertion (block idle sleep while active)

    func beginPreventSleep() {
        guard !holdingAssertion else { return }
        let reason = "Vigilant is keeping this Mac active" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        holdingAssertion = (result == kIOReturnSuccess)
    }

    func endPreventSleep() {
        guard holdingAssertion else { return }
        IOPMAssertionRelease(assertionID)
        holdingAssertion = false
        assertionID = 0
    }
}
