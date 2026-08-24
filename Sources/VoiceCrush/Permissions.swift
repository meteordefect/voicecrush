import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics
import Speech

enum Permissions {
    static func requestLaunchPermissions() async {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { _ in
                continuation.resume()
            }
        }
        if !CGPreflightPostEventAccess(),
           UserDefaults.standard.bool(forKey: "didAskInputMonitoring") == false {
            UserDefaults.standard.set(true, forKey: "didAskInputMonitoring")
            _ = CGRequestPostEventAccess()
        }
    }

    static func openAccessibilitySettings() {
        openPrivacyPane("Privacy_Accessibility")
    }

    static func openInputMonitoringSettings() {
        _ = CGRequestPostEventAccess()
        openPrivacyPane("Privacy_ListenEvent")
    }

    static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    static var canPostEvents: Bool {
        CGPreflightPostEventAccess()
    }

    private static func openPrivacyPane(_ anchor: String) {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ]
        for value in urls {
            if let url = URL(string: value) {
                NSWorkspace.shared.open(url)
                return
            }
        }
    }
}
