import Cocoa
import SwiftUI
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import IOSurface
import QuartzCore

@MainActor
public final class PinnedWindowController: NSObject, ObservableObject {
    public let windowID: CGWindowID
    public let pid: pid_t
    public let ownerName: String
    public let appIcon: NSImage?

    @Published public var windowTitle: String
    @Published public var mode: PinMode {
        didSet {
            handleModeChange(from: oldValue, to: mode)
        }
    }
    @Published public var opacity: Double = 1.0 {
        didSet {
            updateOverlayPresentation()
        }
    }
    @Published public var isTargetObstructed: Bool = false
    @Published public var isCapturingStream: Bool = false
    @Published public var hasCapturedFrame: Bool = false
    @Published public var quartzBounds: CGRect

    public var onRequestUnpin: ((CGWindowID) -> Void)?

    private var overlayWindow: PinOverlayWindow!
    private var pillWindow: ControlPillWindow!
    private var pipFrame: NSRect?
    private var lastAutoRaiseTime: Date = .distantPast

    // ScreenCaptureKit stream state
    private var scStream: SCStream?
    private var streamOutput: StreamOutputHandler?
    private var lastConfiguredPixelSize: CGSize = .zero
    private var isStartingStream: Bool = false

    public var displayTitle: String {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ownerName : trimmed
    }

    public init(windowInfo: WindowInfo, initialMode: PinMode = .inPlace) {
        self.windowID = windowInfo.id
        self.pid = windowInfo.pid
        self.ownerName = windowInfo.ownerName
        self.appIcon = windowInfo.appIcon
        self.windowTitle = windowInfo.displayTitle
        self.mode = initialMode
        self.quartzBounds = windowInfo.quartzBounds
        if initialMode == .ghost {
            self.opacity = 0.78
        }
        super.init()

        setupWindows()
        updateOverlayPresentation()
        startStreamIfNeeded()
    }

    // MARK: - Window Setup

    private func setupWindows() {
        let initialFrame = WindowInfo.quartzToCocoa(quartzBounds)

        overlayWindow = PinOverlayWindow(frame: initialFrame)
        overlayWindow.onLeftClickOverlay = { [weak self] in
            self?.handleOverlayClicked()
        }
        overlayWindow.onUserMovedOrResizedPiP = { [weak self] newFrame in
            guard let self = self else { return }
            if self.mode == .pip {
                self.pipFrame = newFrame
                self.repositionPillWindow()
            }
        }

        pillWindow = ControlPillWindow(controller: self)

        overlayWindow.orderFrontRegardless()
        repositionPillWindow()
        pillWindow.orderFrontRegardless()
    }

    public func closeAndCleanup() {
        stopStream()
        pillWindow?.orderOut(nil)
        overlayWindow?.orderOut(nil)
        pillWindow = nil
        overlayWindow = nil
    }

    // MARK: - Mode & Interaction

    private func handleModeChange(from oldMode: PinMode, to newMode: PinMode) {
        if newMode == .ghost && opacity > 0.95 {
            opacity = 0.78
        } else if oldMode == .ghost && newMode != .ghost && abs(opacity - 0.78) < 0.05 {
            opacity = 1.0
        }

        if newMode == .pip && pipFrame == nil {
            let fullFrame = WindowInfo.quartzToCocoa(quartzBounds)
            let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let aspect = max(0.4, min(2.5, fullFrame.width / max(1, fullFrame.height)))
            let pipW = max(360, min(640, round(fullFrame.width * 0.42)))
            let pipH = max(220, min(520, round(pipW / aspect)))
            let pipX = screenFrame.maxX - pipW - 28
            let pipY = screenFrame.minY + 36
            pipFrame = NSRect(x: pipX, y: pipY, width: pipW, height: pipH)
        }

        startStreamIfNeeded()
        updateOverlayPresentation()
    }

    private func handleOverlayClicked() {
        switch mode {
        case .inPlace:
            // Bring the real target window to the front and hand over native control
            focusRealWindow()
        case .pip:
            // Single click drags PiP; button or double click focuses real window
            break
        case .ghost, .autoRaise:
            break
        }
    }

    public func focusRealWindow() {
        WindowDiscovery.shared.raiseAndFocusWindow(
            windowID: windowID,
            pid: pid,
            targetBounds: quartzBounds
        )
        // Optimistically mark unobstructed so the user can interact with the native window immediately
        isTargetObstructed = false
        updateOverlayPresentation()
    }

    // MARK: - Live State Synchronization

    public func syncLiveState(screenRecordingGranted: Bool) {
        let state = WindowDiscovery.shared.queryLiveWindowState(windowID: windowID)
        if !state.exists {
            // Target window was closed
            onRequestUnpin?(windowID)
            return
        }

        if let newTitle = state.title, !newTitle.isEmpty, newTitle != windowTitle {
            windowTitle = newTitle
        }

        if let liveBounds = state.quartzBounds, state.isOnScreen {
            if liveBounds != quartzBounds {
                let sizeChanged = abs(liveBounds.width - quartzBounds.width) > 2 ||
                                  abs(liveBounds.height - quartzBounds.height) > 2
                quartzBounds = liveBounds
                if sizeChanged {
                    updateStreamResolutionIfNeeded()
                }
            }
        }

        let wasObstructed = isTargetObstructed
        isTargetObstructed = state.isObstructed || !state.isOnScreen

        if mode == .autoRaise && isTargetObstructed && state.isOnScreen {
            let now = Date()
            if now.timeIntervalSince(lastAutoRaiseTime) > 0.65 {
                lastAutoRaiseTime = now
                WindowDiscovery.shared.raiseAndFocusWindow(
                    windowID: windowID,
                    pid: pid,
                    targetBounds: quartzBounds
                )
            }
        }

        if screenRecordingGranted && !isCapturingStream && !isStartingStream && mode != .autoRaise {
            startStreamIfNeeded()
        }

        if wasObstructed != isTargetObstructed || mode != .pip {
            updateOverlayPresentation()
        }
    }

    public func updateOverlayPresentation() {
        guard let overlayWindow = overlayWindow else { return }

        let targetFrame: NSRect
        if mode == .pip, let customPiP = pipFrame {
            targetFrame = customPiP
        } else {
            targetFrame = WindowInfo.quartzToCocoa(quartzBounds)
        }

        if overlayWindow.frame != targetFrame {
            overlayWindow.setFrame(targetFrame, display: true)
        }
        repositionPillWindow()

        let hasScreenPermission = CGPreflightScreenCaptureAccess()

        switch mode {
        case .inPlace:
            overlayWindow.isPiPMode = false
            overlayWindow.borderView.accentColor = NSColor.systemIndigo
            overlayWindow.borderView.modeBadgeText = isTargetObstructed ? "📌 Pinned (Click to Interact)" : "📌 Pinned (Native Active)"

            if isTargetObstructed {
                // Another window is covering the target window -> show live mirror on top!
                overlayWindow.videoLayer.isHidden = !hasCapturedFrame
                overlayWindow.videoLayer.opacity = Float(opacity)
                overlayWindow.ignoresMouseEvents = false
                overlayWindow.setFallbackBannerVisible(!hasScreenPermission && !hasCapturedFrame)
            } else {
                // Target window is unobstructed -> pass all mouse events directly to the real window!
                overlayWindow.videoLayer.isHidden = true
                overlayWindow.ignoresMouseEvents = true
                overlayWindow.setFallbackBannerVisible(false)
            }

        case .ghost:
            overlayWindow.isPiPMode = false
            overlayWindow.borderView.accentColor = NSColor.systemCyan
            overlayWindow.borderView.modeBadgeText = "👻 Ghost Click-Through (\(Int(opacity * 100))%)"
            overlayWindow.videoLayer.isHidden = !hasCapturedFrame
            overlayWindow.videoLayer.opacity = Float(opacity)
            overlayWindow.ignoresMouseEvents = true
            overlayWindow.setFallbackBannerVisible(!hasScreenPermission && !hasCapturedFrame)

        case .pip:
            overlayWindow.isPiPMode = true
            overlayWindow.borderView.accentColor = NSColor.systemOrange
            overlayWindow.borderView.modeBadgeText = "🖼️ PiP — Drag to Move, Corner to Resize"
            overlayWindow.videoLayer.isHidden = !hasCapturedFrame
            overlayWindow.videoLayer.opacity = Float(opacity)
            overlayWindow.ignoresMouseEvents = false
            overlayWindow.setFallbackBannerVisible(!hasScreenPermission && !hasCapturedFrame)

        case .autoRaise:
            overlayWindow.isPiPMode = false
            overlayWindow.borderView.accentColor = NSColor.systemGreen
            overlayWindow.borderView.modeBadgeText = "⚡ Auto-Raise Active"
            overlayWindow.videoLayer.isHidden = true
            overlayWindow.ignoresMouseEvents = true
            overlayWindow.setFallbackBannerVisible(false)
        }

        overlayWindow.borderView.needsDisplay = true
    }

    private func repositionPillWindow() {
        guard let overlayWindow = overlayWindow, let pillWindow = pillWindow else { return }
        let oFrame = overlayWindow.frame
        let pillSize = pillWindow.frame.size
        let pillX = max(12, min(oFrame.maxX - pillSize.width - 10, (NSScreen.main?.frame.maxX ?? 2500) - pillSize.width - 8))
        // Place pill neatly along the top-right border of the pinned window
        let pillY = oFrame.maxY - pillSize.height - 6
        let newPillFrame = NSRect(origin: NSPoint(x: pillX, y: pillY), size: pillSize)
        if pillWindow.frame != newPillFrame {
            pillWindow.setFrame(newPillFrame, display: true)
        }
    }

    // MARK: - ScreenCaptureKit 60fps Live Capture

    public func startStreamIfNeeded() {
        guard mode != .autoRaise else { return }
        guard !isCapturingStream && !isStartingStream else { return }
        guard CGPreflightScreenCaptureAccess() else { return }

        isStartingStream = true
        let targetWID = self.windowID

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.isStartingStream = false }

            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard let scWindow = content.windows.first(where: { $0.windowID == targetWID }) else {
                    return
                }

                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let scale = NSScreen.main?.backingScaleFactor ?? 2.0
                let config = SCStreamConfiguration()
                let pixelW = max(200, Int(self.quartzBounds.width * scale))
                let pixelH = max(150, Int(self.quartzBounds.height * scale))
                config.width = pixelW
                config.height = pixelH
                config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
                config.showsCursor = false
                config.ignoreShadowsSingleWindow = true
                config.queueDepth = 5
                self.lastConfiguredPixelSize = CGSize(width: pixelW, height: pixelH)

                // Capture an immediate initial frame so even static windows appear at millisecond 0
                if let cgImage = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    self.overlayWindow?.videoLayer.contents = cgImage
                    CATransaction.commit()
                    self.hasCapturedFrame = true
                    self.updateOverlayPresentation()
                }

                let outputHandler = StreamOutputHandler { [weak self] surface in
                    guard let self = self, let videoLayer = self.overlayWindow?.videoLayer else { return }
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    videoLayer.contents = surface
                    CATransaction.commit()
                    if !self.hasCapturedFrame {
                        self.hasCapturedFrame = true
                        self.updateOverlayPresentation()
                    }
                }

                let stream = SCStream(filter: filter, configuration: config, delegate: outputHandler)
                try stream.addStreamOutput(outputHandler, type: .screen, sampleHandlerQueue: .main)
                try await stream.startCapture()

                self.streamOutput = outputHandler
                self.scStream = stream
                self.isCapturingStream = true
                self.updateOverlayPresentation()
            } catch {
                self.isCapturingStream = false
            }
        }
    }

    private func updateStreamResolutionIfNeeded() {
        guard let stream = scStream else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let pixelW = max(200, Int(quartzBounds.width * scale))
        let pixelH = max(150, Int(quartzBounds.height * scale))
        guard abs(CGFloat(pixelW) - lastConfiguredPixelSize.width) > 8 ||
              abs(CGFloat(pixelH) - lastConfiguredPixelSize.height) > 8 else {
            return
        }
        lastConfiguredPixelSize = CGSize(width: pixelW, height: pixelH)

        let config = SCStreamConfiguration()
        config.width = pixelW
        config.height = pixelH
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.queueDepth = 5

        Task {
            try? await stream.updateConfiguration(config)
        }
    }

    public func stopStream() {
        if let stream = scStream {
            Task {
                try? await stream.stopCapture()
            }
        }
        scStream = nil
        streamOutput = nil
        isCapturingStream = false
    }
}

// MARK: - SCStreamOutput Handler

private final class StreamOutputHandler: NSObject, SCStreamOutput, SCStreamDelegate {
    private let onFrameSurface: @MainActor (IOSurfaceRef) -> Void

    init(onFrameSurface: @escaping @MainActor (IOSurfaceRef) -> Void) {
        self.onFrameSurface = onFrameSurface
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let first = attachments.first,
              let statusRaw = first[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw),
              status == .complete else {
            return
        }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let surfaceRef = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
            return
        }

        DispatchQueue.main.async { [onFrameSurface] in
            onFrameSurface(surfaceRef)
        }
    }
}

// MARK: - PinOverlayWindow

final class PinOverlayWindow: NSWindow {
    let videoLayer = CALayer()
    let borderView = PinBorderView()
    private var fallbackHostingView: NSHostingView<AnyView>?

    var isPiPMode: Bool = false
    var onLeftClickOverlay: (() -> Void)?
    var onUserMovedOrResizedPiP: ((NSRect) -> Void)?

    private var isResizingPiP = false
    private var isDraggingPiP = false
    private var dragStartMouse: NSPoint = .zero
    private var dragStartFrame: NSRect = .zero

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let rootView = NSView(frame: NSRect(origin: .zero, size: frame.size))
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 10
        rootView.layer?.masksToBounds = true
        rootView.autoresizingMask = [.width, .height]

        videoLayer.frame = rootView.bounds
        videoLayer.contentsGravity = .resize
        videoLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        videoLayer.isHidden = true
        rootView.layer?.addSublayer(videoLayer)

        borderView.frame = rootView.bounds
        borderView.autoresizingMask = [.width, .height]
        rootView.addSubview(borderView)

        self.contentView = rootView
    }

    func setFallbackBannerVisible(_ visible: Bool) {
        if visible {
            if fallbackHostingView == nil, let contentView = contentView {
                let banner = FallbackPermissionOverlayView(
                    onBringToFront: { [weak self] in
                        self?.onLeftClickOverlay?()
                    },
                    onEnableScreenRecording: {
                        CGRequestScreenCaptureAccess()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
                let hosting = NSHostingView(rootView: AnyView(banner))
                hosting.frame = contentView.bounds
                hosting.autoresizingMask = [.width, .height]
                contentView.addSubview(hosting, positioned: .above, relativeTo: borderView)
                fallbackHostingView = hosting
            }
            fallbackHostingView?.isHidden = false
        } else {
            fallbackHostingView?.isHidden = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isPiPMode {
            let localPt = contentView?.convert(event.locationInWindow, from: nil) ?? .zero
            // Bottom-right 28x28 corner resizes PiP window
            if localPt.x >= frame.width - 28 && localPt.y <= 28 {
                isResizingPiP = true
                isDraggingPiP = false
            } else {
                isResizingPiP = false
                isDraggingPiP = true
            }
            dragStartMouse = NSEvent.mouseLocation
            dragStartFrame = frame
            if event.clickCount == 2 {
                onLeftClickOverlay?()
            }
        } else {
            onLeftClickOverlay?()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPiPMode else { return }
        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - dragStartMouse.x
        let dy = currentMouse.y - dragStartMouse.y

        if isResizingPiP {
            let newW = max(240, dragStartFrame.width + dx)
            let newH = max(150, dragStartFrame.height - dy)
            let newY = dragStartFrame.maxY - newH
            let newFrame = NSRect(x: dragStartFrame.origin.x, y: newY, width: newW, height: newH)
            setFrame(newFrame, display: true)
            onUserMovedOrResizedPiP?(newFrame)
        } else if isDraggingPiP {
            let newFrame = NSRect(
                x: dragStartFrame.origin.x + dx,
                y: dragStartFrame.origin.y + dy,
                width: dragStartFrame.width,
                height: dragStartFrame.height
            )
            setFrame(newFrame, display: true)
            onUserMovedOrResizedPiP?(newFrame)
        }
    }

    override func mouseUp(with event: NSEvent) {
        isResizingPiP = false
        isDraggingPiP = false
    }
}

final class PinBorderView: NSView {
    var accentColor: NSColor = .systemIndigo
    var modeBadgeText: String = "📌 Pinned"

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let inset = bounds.insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: inset, xRadius: 10, yRadius: 10)
        accentColor.withAlphaComponent(0.92).setStroke()
        path.lineWidth = 3.5
        path.stroke()

        // Draw subtle resize grip in bottom-right corner
        let gripRect = NSRect(x: bounds.width - 18, y: 6, width: 12, height: 12)
        accentColor.withAlphaComponent(0.7).setStroke()
        let gripPath = NSBezierPath()
        gripPath.move(to: NSPoint(x: gripRect.minX, y: gripRect.minY))
        gripPath.line(to: NSPoint(x: gripRect.maxX, y: gripRect.maxY))
        gripPath.move(to: NSPoint(x: gripRect.minX + 5, y: gripRect.minY))
        gripPath.line(to: NSPoint(x: gripRect.maxX, y: gripRect.maxY - 5))
        gripPath.lineWidth = 2.0
        gripPath.stroke()
    }
}

// MARK: - Floating Top-Right Control Pill Window

final class ControlPillWindow: NSPanel {
    init(controller: PinnedWindowController) {
        let rect = NSRect(x: 0, y: 0, width: 390, height: 34)
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.becomesKeyOnlyIfNeeded = true

        let pillView = ControlPillBarView(controller: controller)
        let hosting = NSHostingView(rootView: pillView)
        hosting.frame = NSRect(origin: .zero, size: rect.size)
        self.contentView = hosting
    }
}

private struct ControlPillBarView: View {
    @ObservedObject var controller: PinnedWindowController

    var body: some View {
        HStack(spacing: 6) {
            if let icon = controller.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.cyan)
            }

            Text(controller.ownerName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(maxWidth: 85, alignment: .leading)

            Divider()
                .frame(height: 14)
                .background(Color.white.opacity(0.25))

            ForEach(PinMode.allCases) { pinMode in
                Button {
                    controller.mode = pinMode
                } label: {
                    Text(pinMode.rawValue)
                        .font(.system(size: 10, weight: controller.mode == pinMode ? .bold : .medium))
                        .foregroundColor(controller.mode == pinMode ? .black : .white.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 5)
                                .fill(controller.mode == pinMode ? Color.cyan : Color.white.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .help(pinMode.subtitle)
            }

            // Opacity quick cycle button
            Button {
                if controller.opacity > 0.9 {
                    controller.opacity = 0.75
                } else if controller.opacity > 0.6 {
                    controller.opacity = 0.50
                } else {
                    controller.opacity = 1.0
                }
            } label: {
                Text("\(Int(controller.opacity * 100))%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Click to cycle window opacity (100% / 75% / 50%)")

            // Unpin button
            Button {
                controller.onRequestUnpin?(controller.windowID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.red.opacity(0.85)))
            }
            .buttonStyle(.plain)
            .help("Unpin window")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.86))
                .overlay(
                    Capsule()
                        .strokeBorder(Color.cyan.opacity(0.6), lineWidth: 1)
                )
        )
    }
}

private struct FallbackPermissionOverlayView: View {
    let onBringToFront: () -> Void
    let onEnableScreenRecording: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
            VStack(spacing: 12) {
                Image(systemName: "pin.circle.fill")
                    .font(.system(size: 36))
                    .foregroundColor(.cyan)

                Text("Pinned Window is Covered by Another App")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)

                Text("Click below to bring the window to the front immediately, or enable Screen Recording so PinTop can stream this window live on top even while you type in overlapping apps.")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)

                HStack(spacing: 12) {
                    Button(action: onBringToFront) {
                        Label("Bring Window to Front", systemImage: "macwindow.on.rectangle")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.cyan))
                            .foregroundColor(.black)
                    }
                    .buttonStyle(.plain)

                    Button(action: onEnableScreenRecording) {
                        Label("Enable 60fps Live Mirror", systemImage: "record.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.18)))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
    }
}
