import AppKit
import ApplicationServices

enum TextInjector {
    enum Result {
        case pasted
        case needsAccessibility
        case failed
    }

    struct Target {
        let app: NSRunningApplication
        let element: AXUIElement?

        var name: String {
            app.localizedName ?? app.bundleIdentifier ?? "app"
        }
    }

    static func captureTarget() -> Target? {
        guard let app = lastUserApp() else { return nil }
        return Target(app: app, element: focusedElement(ownedBy: app))
    }

    static func lastUserApp() -> NSRunningApplication? {
        if let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != "com.voicecrush.app" {
            return front
        }
        return NSWorkspace.shared.runningApplications.first {
            $0.isActive && $0.bundleIdentifier != "com.voicecrush.app" && $0.activationPolicy == .regular
        }
    }

    static func focusedElement(ownedBy app: NSRunningApplication) -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard error == .success, let focused else { return nil }
        let element = focused as! AXUIElement
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid == app.processIdentifier else { return nil }
        return element
    }

    @MainActor
    static func paste(_ text: String, into target: Target?, waitForModifiers: Bool = true) async -> Result {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failed }

        if waitForModifiers {
            try? await Task.sleep(for: .milliseconds(280))
        }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)

        let target = target ?? captureTarget()
        if let target, !target.app.isTerminated {
            NSApp.yieldActivation(to: target.app)
            target.app.activate()
            try? await Task.sleep(for: .milliseconds(180))
            if let element = target.element ?? focusedElement(ownedBy: target.app) {
                AXUIElementSetAttributeValue(
                    element,
                    kAXFocusedAttribute as CFString,
                    kCFBooleanTrue
                )
                try? await Task.sleep(for: .milliseconds(60))
                if insertSelectedText(trimmed, into: element) {
                    log("ax insert into \(target.name)")
                    restorePasteboard(previous)
                    return .pasted
                }
            }
        }

        try? await Task.sleep(for: .milliseconds(60))
        let pid = target?.app.processIdentifier
        let appName = target?.name
        if pasteWithSystemEvents(into: appName) {
            log("system events paste into \(appName ?? "front")")
        } else {
            postCommandV(to: pid)
            typeUnicode(trimmed, to: pid)
            log("fallback type into \(appName ?? "front") pid=\(pid ?? -1)")
        }

        try? await Task.sleep(for: .milliseconds(1500))
        restorePasteboard(previous)
        return .pasted
    }

    private static func restorePasteboard(_ previous: String?) {
        guard let previous else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(previous, forType: .string)
    }

    @MainActor
    static func pressReturn(into target: Target?) async {
        let pid = target?.app.processIdentifier
        let key: CGKeyCode = 36
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        if let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
            if let pid, pid > 0 { down.postToPid(pid) }
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            if let pid, pid > 0 { up.postToPid(pid) }
            up.post(tap: .cghidEventTap)
        }
        let script = "tell application \"System Events\" to key code 36"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    private static func insertSelectedText(_ text: String, into element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != pid_t(ProcessInfo.processInfo.processIdentifier) else { return false }
        let error = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return error == .success
    }

    private static func pasteWithSystemEvents(into appName: String?) -> Bool {
        let quoted = (appName ?? "").replacingOccurrences(of: "\"", with: "")
        let source: String
        if quoted.isEmpty {
            source = "tell application \"System Events\" to keystroke \"v\" using command down"
        } else {
            source = """
            tell application "\(quoted)" to activate
            delay 0.12
            tell application "System Events"
              tell process "\(quoted)"
                set frontmost to true
                keystroke "v" using command down
              end tell
            end tell
            """
        }
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return false }
        _ = script.executeAndReturnError(&error)
        if let error {
            log("applescript error \(error)")
            return false
        }
        return true
    }

    private static func postCommandV(to pid: pid_t?) {
        let sources: [CGEventSourceStateID] = [.hidSystemState, .combinedSessionState]
        let taps: [CGEventTapLocation] = [.cghidEventTap, .cgSessionEventTap]
        let command: CGKeyCode = 55
        let keyV: CGKeyCode = 9
        let commandFlag = CGEventFlags([.maskCommand, CGEventFlags(rawValue: 0x000008)])
        let keys: [(CGKeyCode, Bool, CGEventFlags)] = [
            (command, true, .maskCommand),
            (keyV, true, commandFlag),
            (keyV, false, commandFlag),
            (command, false, [])
        ]

        for state in sources {
            guard let source = CGEventSource(stateID: state) else { continue }
            source.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalKeyboardEvents, .permitLocalMouseEvents],
                state: .eventSuppressionStateSuppressionInterval
            )
            for (key, down, flags) in keys {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
                    continue
                }
                event.flags = flags
                if let pid, pid > 0 {
                    event.postToPid(pid)
                }
                for tap in taps {
                    event.post(tap: tap)
                }
            }
        }
    }

    private static func typeUnicode(_ text: String, to pid: pid_t?) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let scalars = Array(text.utf16)
        var index = 0
        while index < scalars.count {
            let end = min(index + 16, scalars.count)
            var slice = Array(scalars[index..<end])
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
                if let pid, pid > 0 {
                    down.postToPid(pid)
                }
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
                if let pid, pid > 0 {
                    up.postToPid(pid)
                }
                up.post(tap: .cghidEventTap)
            }
            index = end
        }
    }

    private static func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        let url = URL(fileURLWithPath: "/tmp/voicecrush-paste.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    defer { try? handle.close() }
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: url)
            }
        }
    }
}
