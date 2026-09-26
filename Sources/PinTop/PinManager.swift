import Cocoa
import ApplicationServices

@MainActor
public final class PinManager: ObservableObject {
    public static let shared = PinManager()

    @Published public var availableWindows: [WindowInfo] = []
    @Published public var pinnedControllers: [PinnedWindowController] = []
    @Published public var hasScreenRecordingPermission: Bool = false
    @Published public var hasAccessibilityPermission: Bool = false
    @Published public var searchQuery: String = ""
    @Published public var filterBrowsersOnly: Bool = false
    @Published public var statusMessage: String?

    public var onPinnedCountChanged: ((Int) -> Void)?

    private var syncTimer: Timer?
    private var listRefreshCounter: Int = 0

    private init() {
        refreshPermissions()
        refreshWindows()
        setupWorkspaceNotifications()
        setupHotKeys()
        startSyncTimer()
    }

    public var filteredWindows: [WindowInfo] {
        availableWindows.filter { win in
            if filterBrowsersOnly && !win.isChromeOrBrowser {
                return false
            }
            let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !q.isEmpty {
                let matchOwner = win.ownerName.lowercased().contains(q)
                let matchTitle = win.displayTitle.lowercased().contains(q)
                let matchRegion = win.regionDescription.lowercased().contains(q)
                return matchOwner || matchTitle || matchRegion
            }
            return true
        }
    }

    public func isPinned(_ windowID: CGWindowID) -> Bool {
        pinnedControllers.contains { $0.windowID == windowID }
    }

    public func controller(for windowID: CGWindowID) -> PinnedWindowController? {
        pinnedControllers.first { $0.windowID == windowID }
    }

    // MARK: - Pin / Unpin Operations

    public func pinWindow(_ info: WindowInfo, mode: PinMode = .inPlace) {
        ScreenHighlightOverlay.shared.hideHoverPreview()

        if let existing = controller(for: info.id) {
            existing.mode = mode
            showTransientStatus("Updated '\(info.displayTitle)' to \(mode.rawValue) mode")
            return
        }

        let controller = PinnedWindowController(windowInfo: info, initialMode: mode)
        controller.onRequestUnpin = { [weak self] wid in
            self?.unpinWindow(windowID: wid)
        }
        pinnedControllers.append(controller)
        onPinnedCountChanged?(pinnedControllers.count)
        showTransientStatus("📌 Pinned '\(info.displayTitle)' (\(mode.rawValue))")
    }

    public func togglePin(_ info: WindowInfo, defaultMode: PinMode = .inPlace) {
        if isPinned(info.id) {
            unpinWindow(windowID: info.id)
        } else {
            pinWindow(info, mode: defaultMode)
        }
    }

    public func unpinWindow(windowID: CGWindowID) {
        guard let idx = pinnedControllers.firstIndex(where: { $0.windowID == windowID }) else { return }
        let removed = pinnedControllers.remove(at: idx)
        removed.closeAndCleanup()
        onPinnedCountChanged?(pinnedControllers.count)
        showTransientStatus("Unpinned '\(removed.displayTitle)'")
    }

    public func unpinAll() {
        guard !pinnedControllers.isEmpty else { return }
        for controller in pinnedControllers {
            controller.closeAndCleanup()
        }
        pinnedControllers.removeAll()
        onPinnedCountChanged?(0)
        showTransientStatus("Unpinned all windows")
    }

    public func togglePinForActiveWindow() {
        guard let candidate = WindowDiscovery.shared.frontmostCandidateWindow() else {
            showTransientStatus("No active window found to pin")
            return
        }
        togglePin(candidate, defaultMode: .inPlace)
    }

    public func startInteractiveWindowPicker() {
        ScreenHighlightOverlay.shared.startInteractivePicker { [weak self] selectedWindow in
            guard let self = self else { return }
            self.pinWindow(selectedWindow, mode: .inPlace)
        }
    }

    public func toggleGhostModeForAll() {
        guard !pinnedControllers.isEmpty else {
            showTransientStatus("Pin a window first to toggle Ghost Click-Through mode")
            return
        }
        let anyNotGhost = pinnedControllers.contains { $0.mode != .ghost }
        let targetMode: PinMode = anyNotGhost ? .ghost : .inPlace
        for controller in pinnedControllers {
            controller.mode = targetMode
        }
        showTransientStatus(targetMode == .ghost ? "👻 Enabled Ghost Click-Through on pinned windows" : "📌 Restored 1:1 Interactive mode")
    }

    // MARK: - Discovery & Sync

    public func refreshPermissions() {
        hasScreenRecordingPermission = CGPreflightScreenCaptureAccess()
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    public func refreshWindows() {
        refreshPermissions()
        let pinnedSet = Set(pinnedControllers.map { $0.windowID })
        let discovered = WindowDiscovery.shared.discoverWindows(pinnedIDs: pinnedSet)
        if discovered != availableWindows {
            availableWindows = discovered
        }
    }

    public func requestScreenRecordingPermission() {
        _ = CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissions()
    }

    public func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissions()
    }

    private func setupWorkspaceNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.syncPinnedWindowsNow()
            }
        }
    }

    private func setupHotKeys() {
        let hk = HotKeyManager.shared
        hk.onToggleActiveWindowPin = { [weak self] in
            self?.togglePinForActiveWindow()
        }
        hk.onStartWindowPicker = { [weak self] in
            self?.startInteractiveWindowPicker()
        }
        hk.onToggleGhostMode = { [weak self] in
            self?.toggleGhostModeForAll()
        }
        hk.onUnpinAll = { [weak self] in
            self?.unpinAll()
        }
        hk.registerGlobalHotKeys()
    }

    private func startSyncTimer() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.14, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.syncPinnedWindowsNow()
                self.listRefreshCounter += 1
                if self.listRefreshCounter >= 12 {
                    self.listRefreshCounter = 0
                    self.refreshWindows()
                }
            }
        }
    }

    public func syncPinnedWindowsNow() {
        let screenGranted = CGPreflightScreenCaptureAccess()
        if screenGranted != hasScreenRecordingPermission {
            hasScreenRecordingPermission = screenGranted
        }
        let axGranted = AXIsProcessTrusted()
        if axGranted != hasAccessibilityPermission {
            hasAccessibilityPermission = axGranted
        }
        for controller in pinnedControllers {
            controller.syncLiveState(screenRecordingGranted: screenGranted)
        }
    }

    private func showTransientStatus(_ message: String) {
        statusMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if self.statusMessage == message {
                self.statusMessage = nil
            }
        }
    }
}
