import AppKit
import ApplicationServices

enum TextInjector {
    enum Result: Equatable {
        case pasted
        case needsAccessibility
        case needsInputMonitoring
        case failed
    }

    struct Target {
        let app: NSRunningApplication
        let element: AXUIElement?

        var name: String {
            app.localizedName ?? app.bundleIdentifier ?? "app"
        }

        var isTerminal: Bool {
            TextInjector.isTerminal(app)
        }

        var prefersTypedInput: Bool {
            TextInjector.prefersTypedInput(app)
        }

        var isBrowser: Bool {
            TextInjector.isBrowser(app)
        }
    }

    private static let terminalBundleIds: Set<String> = [
        "com.mitchellh.ghostty",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "org.alacritty",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp-Stable",
        "com.github.wez.wezterm"
    ]

    static func isTerminal(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier?.lowercased() else { return false }
        if terminalBundleIds.contains(where: { $0.lowercased() == id }) {
            return true
        }
        return id.contains("ghostty") || id.contains("iterm") || id.contains("alacritty") || id.contains("kitty")
    }

    static func prefersTypedInput(_ app: NSRunningApplication?) -> Bool {
        if isTerminal(app) { return true }
        let id = app?.bundleIdentifier?.lowercased() ?? ""
        let name = app?.localizedName?.lowercased() ?? ""
        return name == "cursor"
            || id.contains("cursor")
            || id.contains("todesktop")
            || id.contains("vscode")
            || name.contains("windsurf")
    }

    static func isBrowser(_ app: NSRunningApplication?) -> Bool {
        let id = app?.bundleIdentifier?.lowercased() ?? ""
        let name = app?.localizedName?.lowercased() ?? ""
        return id.contains("safari")
            || id.contains("chrome")
            || id.contains("brave")
            || id.contains("firefox")
            || id.contains("orion")
            || id.contains("edge")
            || id.contains("arc")
            || id.contains("comet")
            || name.contains("brave")
            || name.contains("safari")
            || name.contains("chrome")
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
            await waitUntilModifiersClear()
        }

        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)

        let target = target ?? captureTarget()
        await bringForwardIfNeeded(target)
        await waitUntilModifiersClear()

        let appName = target?.name ?? "front"
        log("paste start ax=\(Permissions.hasAccessibility) post=\(Permissions.canPostEvents) target=\(appName)")

        // Native text views only. Browsers and GPU/Electron apps report AX success
        // without inserting into the real field.
        if target?.isBrowser != true, target?.prefersTypedInput != true,
           let target, let element = target.element ?? focusedElement(ownedBy: target.app) {
            AXUIElementSetAttributeValue(
                element,
                kAXFocusedAttribute as CFString,
                kCFBooleanTrue
            )
            try? await Task.sleep(for: .milliseconds(40))
            if insertSelectedText(trimmed, into: element) {
                log("ax insert into \(target.name)")
                restorePasteboard(previous)
                return .pasted
            }
        }

        if postCommandV() {
            log("hid cmd-v into \(appName)")
            try? await Task.sleep(for: .milliseconds(600))
            restorePasteboard(previous)
            return .pasted
        }

        switch pasteWithSystemEvents(into: appName) {
        case .success:
            log("system events paste into \(appName)")
            try? await Task.sleep(for: .milliseconds(500))
            restorePasteboard(previous)
            return .pasted
        case .denied:
            log("system events denied for \(appName)")
            restorePasteboard(previous)
            return permissionFailure()
        case .failed:
            break
        }

        if target?.prefersTypedInput == true {
            typeUnicode(trimmed)
            log("typed into \(appName)")
            try? await Task.sleep(for: .milliseconds(400))
            restorePasteboard(previous)
            return .pasted
        }

        restorePasteboard(previous)
        return permissionFailure()
    }

    private static func permissionFailure() -> Result {
        if !Permissions.hasAccessibility {
            return .needsAccessibility
        }
        if !Permissions.canPostEvents {
            return .needsInputMonitoring
        }
        return .failed
    }

    private static func restorePasteboard(_ previous: String?) {
        guard let previous else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(previous, forType: .string)
    }

    @MainActor
    private static func waitUntilModifiersClear() async {
        for _ in 0..<40 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty {
                return
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @MainActor
    private static func bringForwardIfNeeded(_ target: Target?) async {
        guard let target, !target.app.isTerminated else { return }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier {
            return
        }
        NSApp.yieldActivation(to: target.app)
        target.app.activate()
        try? await Task.sleep(for: .milliseconds(target.isBrowser || target.prefersTypedInput ? 250 : 180))
    }

    @MainActor
    static func pressReturn(into target: Target?) async {
        let target = target ?? captureTarget()
        await bringForwardIfNeeded(target)
        await waitUntilModifiersClear()
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let key: CGKeyCode = 36
        if let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true) {
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) {
            up.post(tap: .cghidEventTap)
        }
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

    private enum ScriptResult {
        case success
        case denied
        case failed
    }

    private static func pasteWithSystemEvents(into appName: String) -> ScriptResult {
        let quoted = appName.replacingOccurrences(of: "\"", with: "")
        let source = """
        tell application "\(quoted)" to activate
        delay 0.08
        tell application "System Events" to keystroke "v" using command down
        """
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return .failed }
        _ = script.executeAndReturnError(&error)
        if let error {
            log("applescript error \(error)")
            let number = error["NSAppleScriptErrorNumber"] as? Int
            if number == 1002 || number == -1743 {
                return .denied
            }
            return .failed
        }
        return .success
    }

    private static func postCommandV() -> Bool {
        guard Permissions.canPostEvents else { return false }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalKeyboardEvents, .permitLocalMouseEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let keyV: CGKeyCode = 9
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            return false
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    private static func typeUnicode(_ text: String) {
        guard Permissions.canPostEvents else { return }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let scalars = Array(text.utf16)
        var index = 0
        while index < scalars.count {
            let end = min(index + 16, scalars.count)
            var slice = Array(scalars[index..<end])
            if let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) {
                up.keyboardSetUnicodeString(stringLength: slice.count, unicodeString: &slice)
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
