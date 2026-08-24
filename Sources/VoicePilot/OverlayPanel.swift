import AppKit

enum OverlayState: Equatable {
    case idle
    case preparing
    case listening
    case working
    case failed(String)

    var label: String {
        switch self {
        case .idle:
            return "Ready"
        case .preparing:
            return "Preparing…"
        case .listening:
            return "Listening…"
        case .working:
            return "Sending…"
        case .failed(let message):
            return message
        }
    }
}

final class OverlayPanel: NSPanel {
    private let chrome = OverlayChromeView()

    var onToggle: (() -> Void)?
    var onEnter: (() -> Void)?
    var onPointerDown: (() -> Void)?

    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 392, height: 72),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        chrome.onPointerDown = { [weak self] in
            self?.onPointerDown?()
        }
        chrome.onMic = { [weak self] in
            self?.onToggle?()
        }
        chrome.onEnter = { [weak self] in
            self?.onPointerDown?()
            self?.onEnter?()
        }
        contentView = chrome
        reposition()
    }

    func setState(_ state: OverlayState) {
        chrome.state = state
    }

    func setPreview(_ text: String) {
        chrome.preview = text
    }

    func reposition() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }
        let size = frame.size
        let x = visible.midX - size.width / 2
        let y = visible.minY + 72
        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        orderFrontRegardless()
    }
}

private final class OverlayChromeView: NSView {
    var onPointerDown: (() -> Void)?
    var onMic: (() -> Void)?
    var onEnter: (() -> Void)?

    var state: OverlayState = .idle {
        didSet { applyState() }
    }
    var preview: String = "" {
        didSet { applyState() }
    }

    private let blur = NSVisualEffectView()
    private let hairline = NSView()
    private let micButton = CircleActionButton(symbol: "mic.fill")
    private let enterButton = CircleActionButton(symbol: "return")
    private let titleLabel = NSTextField(labelWithString: "Ready")
    private let subtitleLabel = NSTextField(labelWithString: "Hold ⌥  ·  Mic  ·  Enter")
    private var dragStart: NSPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 36
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 36
        addSubview(blur)

        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        addSubview(hairline)

        micButton.toolTip = "Talk"
        enterButton.toolTip = "Enter text"
        micButton.onPress = { [weak self] in
            self?.onPointerDown?()
            self?.onMic?()
        }
        enterButton.onPress = { [weak self] in
            self?.onEnter?()
        }
        addSubview(micButton)
        addSubview(enterButton)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.drawsBackground = false
        addSubview(titleLabel)

        subtitleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.55)
        subtitleLabel.alignment = .center
        subtitleLabel.drawsBackground = false
        addSubview(subtitleLabel)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        blur.frame = bounds
        hairline.frame = NSRect(x: 22, y: bounds.midY, width: bounds.width - 44, height: 1)
        hairline.isHidden = true

        let button: CGFloat = 48
        let inset: CGFloat = 12
        micButton.frame = NSRect(x: inset, y: (bounds.height - button) / 2, width: button, height: button)
        enterButton.frame = NSRect(
            x: bounds.width - inset - button,
            y: (bounds.height - button) / 2,
            width: button,
            height: button
        )

        let textX = micButton.frame.maxX + 10
        let textW = enterButton.frame.minX - textX - 10
        titleLabel.frame = NSRect(x: textX, y: bounds.midY - 2, width: textW, height: 20)
        subtitleLabel.frame = NSRect(x: textX, y: bounds.midY - 22, width: textW, height: 16)
    }

    override func mouseDown(with event: NSEvent) {
        onPointerDown?()
        dragStart = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStart else { return }
        let location = event.locationInWindow
        window.setFrameOrigin(NSPoint(
            x: window.frame.origin.x + location.x - dragStart.x,
            y: window.frame.origin.y + location.y - dragStart.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        dragStart = nil
    }

    private func applyState() {
        let listening = state == .listening
        micButton.accent = listening
            ? NSColor(calibratedRed: 0.90, green: 0.18, blue: 0.22, alpha: 1)
            : NSColor(calibratedWhite: 1, alpha: 0.12)
        micButton.symbolName = listening ? "waveform" : "mic.fill"

        enterButton.accent = NSColor(calibratedRed: 0.82, green: 0.16, blue: 0.20, alpha: 1)

        let live = !preview.isEmpty && state != .idle && state != .preparing
        titleLabel.stringValue = live ? String(preview.prefix(42)) : state.label
        subtitleLabel.stringValue = listening
            ? "Release ⌥ or tap mic to stop"
            : "Mic to talk   ·   Enter to send"
        needsLayout = true
        layer?.borderColor = listening
            ? NSColor(calibratedRed: 0.90, green: 0.18, blue: 0.22, alpha: 0.7).cgColor
            : NSColor.white.withAlphaComponent(0.16).cgColor
    }
}

private final class CircleActionButton: NSView {
    var onPress: (() -> Void)?
    var symbolName: String {
        didSet { needsDisplay = true }
    }
    var accent: NSColor = NSColor.white.withAlphaComponent(0.12) {
        didSet { needsDisplay = true }
    }
    init(symbol: String) {
        symbolName = symbol
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func mouseDown(with event: NSEvent) {
        onPress?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let circle = NSBezierPath(ovalIn: box)
        accent.setFill()
        circle.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        circle.lineWidth = 1
        circle.stroke()

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        image?.isTemplate = true
        let icon = NSSize(width: 18, height: 18)
        let rect = NSRect(
            x: bounds.midX - icon.width / 2,
            y: bounds.midY - icon.height / 2,
            width: icon.width,
            height: icon.height
        )
        NSColor.white.set()
        image?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}
