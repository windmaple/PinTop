import Cocoa

@MainActor
public final class ScreenHighlightOverlay {
    public static let shared = ScreenHighlightOverlay()

    private var previewWindow: NSWindow?
    private var previewView: HighlightBoxView?

    private var pickerWindows: [PickerOverlayWindow] = []
    private var currentHoveredWindow: WindowInfo?
    private var onPickWindow: ((WindowInfo) -> Void)?
    public private(set) var isPicking: Bool = false

    private init() {}

    // MARK: - Row Hover Preview

    public func showHoverPreview(for windowInfo: WindowInfo) {
        guard !isPicking else { return }
        let frame = windowInfo.cocoaFrame

        if previewWindow == nil {
            let win = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            win.isOpaque = false
            win.backgroundColor = .clear
            win.hasShadow = false
            win.ignoresMouseEvents = true
            win.level = .statusBar
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let view = HighlightBoxView(frame: NSRect(origin: .zero, size: frame.size))
            view.autoresizingMask = [.width, .height]
            win.contentView = view

            self.previewWindow = win
            self.previewView = view
        }

        previewView?.labelTitle = "Preview: \(windowInfo.displayTitle) (\(windowInfo.sizeDescription))"
        previewView?.accentColor = NSColor.systemCyan
        previewView?.needsDisplay = true
        previewWindow?.setFrame(frame, display: true)
        previewWindow?.orderFrontRegardless()
    }

    public func hideHoverPreview() {
        previewWindow?.orderOut(nil)
    }

    // MARK: - Interactive Crosshair Window Picker

    public func startInteractivePicker(onSelect: @escaping (WindowInfo) -> Void) {
        hideHoverPreview()
        stopInteractivePicker()

        self.isPicking = true
        self.onPickWindow = onSelect

        for screen in NSScreen.screens {
            let pickerWin = PickerOverlayWindow(screenFrame: screen.frame)
            pickerWin.onMouseMovedAtScreenPoint = { [weak self] point in
                self?.updatePickerHover(at: point)
            }
            pickerWin.onMouseClickedAtScreenPoint = { [weak self] point in
                self?.completePickerSelection(at: point)
            }
            pickerWin.onCancel = { [weak self] in
                self?.stopInteractivePicker()
            }
            pickerWin.makeKeyAndOrderFront(nil)
            pickerWindows.append(pickerWin)
        }

        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
        updatePickerHover(at: NSEvent.mouseLocation)
    }

    public func stopInteractivePicker() {
        guard isPicking else { return }
        isPicking = false
        NSCursor.pop()
        for win in pickerWindows {
            win.orderOut(nil)
        }
        pickerWindows.removeAll()
        currentHoveredWindow = nil
        onPickWindow = nil
    }

    private func updatePickerHover(at screenPoint: NSPoint) {
        let matched = WindowDiscovery.shared.windowAtScreenPoint(screenPoint)
        currentHoveredWindow = matched

        for win in pickerWindows {
            if let matched = matched {
                let localRect = win.convertFromScreen(matched.cocoaFrame)
                win.highlightView.targetRect = localRect
                win.highlightView.targetLabel = "🎯 Click to Pin: \(matched.displayTitle) • \(matched.sizeDescription)   (Esc to cancel)"
            } else {
                win.highlightView.targetRect = nil
                win.highlightView.targetLabel = "Move cursor over any window to pin it • Press Esc to cancel"
            }
            win.highlightView.needsDisplay = true
        }
    }

    private func completePickerSelection(at screenPoint: NSPoint) {
        let target = WindowDiscovery.shared.windowAtScreenPoint(screenPoint) ?? currentHoveredWindow
        let callback = onPickWindow
        stopInteractivePicker()
        if let target = target {
            callback?(target)
        }
    }
}

// MARK: - Views & Windows for Highlighting

private final class HighlightBoxView: NSView {
    var labelTitle: String = ""
    var accentColor: NSColor = .systemCyan

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let inset = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: inset, xRadius: 10, yRadius: 10)

        accentColor.withAlphaComponent(0.10).setFill()
        path.fill()

        accentColor.withAlphaComponent(0.95).setStroke()
        path.lineWidth = 4.0
        path.stroke()

        if !labelTitle.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let size = (labelTitle as NSString).size(withAttributes: attrs)
            let pillRect = NSRect(
                x: 16,
                y: bounds.height - size.height - 28,
                width: min(size.width + 24, bounds.width - 32),
                height: size.height + 12
            )
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: 8, yRadius: 8)
            NSColor.black.withAlphaComponent(0.82).setFill()
            pillPath.fill()
            accentColor.withAlphaComponent(0.9).setStroke()
            pillPath.lineWidth = 1.5
            pillPath.stroke()

            let textRect = NSRect(
                x: pillRect.origin.x + 12,
                y: pillRect.origin.y + 6,
                width: pillRect.width - 24,
                height: size.height
            )
            (labelTitle as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }
}

private final class PickerOverlayWindow: NSWindow {
    let highlightView = PickerCanvasView()
    var onMouseMovedAtScreenPoint: ((NSPoint) -> Void)?
    var onMouseClickedAtScreenPoint: ((NSPoint) -> Void)?
    var onCancel: (() -> Void)?

    init(screenFrame: NSRect) {
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.08)
        self.hasShadow = false
        self.level = .screenSaver
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        highlightView.frame = NSRect(origin: .zero, size: screenFrame.size)
        highlightView.autoresizingMask = [.width, .height]
        self.contentView = highlightView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func mouseMoved(with event: NSEvent) {
        onMouseMovedAtScreenPoint?(NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {
        onMouseClickedAtScreenPoint?(NSEvent.mouseLocation)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        }
    }
}

private final class PickerCanvasView: NSView {
    var targetRect: NSRect?
    var targetLabel: String = "Move cursor over any window to pin it • Press Esc to cancel"

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if let rect = targetRect {
            let clipped = rect.intersection(bounds)
            if !clipped.isNull && clipped.width > 10 && clipped.height > 10 {
                let inset = clipped.insetBy(dx: 2, dy: 2)
                let path = NSBezierPath(roundedRect: inset, xRadius: 10, yRadius: 10)
                NSColor.systemCyan.withAlphaComponent(0.14).setFill()
                path.fill()

                NSColor.systemCyan.setStroke()
                path.lineWidth = 4.0
                path.stroke()
            }
        }

        // Draw top-center instruction banner
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (targetLabel as NSString).size(withAttributes: attrs)
        let bannerW = min(textSize.width + 36, bounds.width - 40)
        let bannerH = textSize.height + 18
        let bannerRect = NSRect(
            x: (bounds.width - bannerW) / 2,
            y: bounds.height - bannerH - 60,
            width: bannerW,
            height: bannerH
        )
        let bannerPath = NSBezierPath(roundedRect: bannerRect, xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.85).setFill()
        bannerPath.fill()
        NSColor.systemCyan.withAlphaComponent(0.9).setStroke()
        bannerPath.lineWidth = 2.0
        bannerPath.stroke()

        let textRect = NSRect(
            x: bannerRect.origin.x + 18,
            y: bannerRect.origin.y + 9,
            width: bannerRect.width - 36,
            height: textSize.height
        )
        (targetLabel as NSString).draw(in: textRect, withAttributes: attrs)
    }
}
