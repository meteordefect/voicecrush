import AppKit

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let overlay = OverlayPanel()
    private let speech = SpeechSession()
    private let hotKey = HotKeyMonitor()
    private var statusItem: NSStatusItem?
    private var isRecording = false
    private var sessionTask: Task<Void, Never>?
    private var target: TextInjector.Target?
    private var lastTranscript = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay.onPointerDown = { [weak self] in
            self?.rememberTarget()
        }
        overlay.onToggle = { [weak self] in
            self?.toggleFromButton()
        }
        overlay.onEnter = { [weak self] in
            self?.enterLastText()
        }
        overlay.reposition()
        overlay.orderFrontRegardless()

        setupStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(userAppActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        rememberTarget()

        Task {
            await Permissions.requestLaunchPermissions()
            self.hotKey.onHoldChanged = { [weak self] holding in
                Task { @MainActor in
                    self?.setRecording(holding)
                }
            }
            self.hotKey.start()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "VC"
        item.button?.toolTip = "VoiceCrush"

        let menu = NSMenu()
        menu.addItem(withTitle: "Hold Right Option to talk", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "Or click the floating pill", action: nil, keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Show button", action: #selector(showButton), keyEquivalent: "b")
        menu.addItem(withTitle: "Open Accessibility settings…", action: #selector(requestAccessibility), keyEquivalent: "")
        menu.addItem(withTitle: "Open Input Monitoring settings…", action: #selector(requestInputMonitoring), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit VoiceCrush", action: #selector(quit), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    @objc private func showButton() {
        overlay.reposition()
        overlay.orderFrontRegardless()
    }

    @objc private func screensChanged() {
        overlay.reposition()
    }

    @objc private func userAppActivated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier != "com.voicecrush.app"
        else { return }
        target = TextInjector.Target(
            app: app,
            element: TextInjector.focusedElement(ownedBy: app)
        )
    }

    @objc private func requestAccessibility() {
        Permissions.openAccessibilitySettings()
    }

    @objc private func requestInputMonitoring() {
        Permissions.openInputMonitoringSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func toggleFromButton() {
        setRecording(!isRecording)
    }

    private func setRecording(_ recording: Bool) {
        if recording {
            startRecording()
        } else {
            stopRecording()
        }
    }

    private func rememberTarget() {
        if let captured = TextInjector.captureTarget() {
            target = captured
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        rememberTarget()
        if let app = target?.app {
            target = TextInjector.Target(
                app: app,
                element: TextInjector.focusedElement(ownedBy: app) ?? target?.element
            )
        }
        isRecording = true
        overlay.setPreview("")
        overlay.setState(.preparing)

        sessionTask?.cancel()
        sessionTask = Task { [speech] in
            do {
                try await speech.start { [weak self] partial in
                    self?.overlay.setPreview(partial)
                    self?.overlay.setState(.listening)
                }
                if !Task.isCancelled, self.isRecording {
                    self.overlay.setState(.listening)
                }
            } catch {
                self.isRecording = false
                self.overlay.setPreview("")
                self.overlay.setState(.failed(error.localizedDescription))
                self.resetIdleSoon()
            }
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        overlay.setState(.working)

        sessionTask?.cancel()
        sessionTask = Task { [speech] in
            let text = await speech.stop()
            if text.isEmpty {
                self.overlay.setPreview("")
                self.overlay.setState(.failed("No speech"))
                self.resetIdleSoon()
                return
            }
            self.lastTranscript = text
            self.overlay.setState(.working)
            self.overlay.setPreview("Pasting into \(self.target?.name ?? "front app")")
            switch await TextInjector.paste(text, into: self.target) {
            case .pasted:
                self.overlay.setPreview("")
                self.overlay.setState(.idle)
            case .needsAccessibility:
                self.overlay.setPreview("")
                self.overlay.setState(.failed("Enable Accessibility"))
                self.resetIdleSoon()
            case .failed:
                self.overlay.setPreview("")
                self.overlay.setState(.failed("Paste failed"))
                self.resetIdleSoon()
            }
        }
    }

    private func enterLastText() {
        rememberTarget()
        sessionTask?.cancel()
        sessionTask = Task {
            if self.isRecording {
                self.isRecording = false
                let text = await self.speech.stop()
                if !text.isEmpty {
                    self.lastTranscript = text
                }
            }
            let text = self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                self.overlay.setState(.failed("Nothing to enter"))
                self.resetIdleSoon()
                return
            }
            self.overlay.setState(.working)
            self.overlay.setPreview("Enter → \(self.target?.name ?? "front app")")
            _ = await TextInjector.paste(text, into: self.target, waitForModifiers: false)
            await TextInjector.pressReturn(into: self.target)
            self.overlay.setPreview("")
            self.overlay.setState(.idle)
        }
    }

    private func resetIdleSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, !self.isRecording else { return }
            self.overlay.setPreview("")
            self.overlay.setState(.idle)
        }
    }
}
