import SwiftUI

@MainActor
public struct DashboardView: View {
    @ObservedObject var manager: PinManager
    var isPopover: Bool = false

    public init(manager: PinManager = .shared, isPopover: Bool = false) {
        self.manager = manager
        self.isPopover = isPopover
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()

            if !manager.hasScreenRecordingPermission || !manager.hasAccessibilityPermission {
                permissionsBanner
                Divider()
            }

            if let status = manager.statusMessage {
                statusToast(status)
                Divider()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !manager.pinnedControllers.isEmpty {
                        pinnedWindowsSection
                    }
                    openWindowsSection
                }
                .padding(16)
            }

            Divider()
            footerSection
        }
        .frame(
            minWidth: isPopover ? 540 : 640,
            idealWidth: isPopover ? 560 : 700,
            minHeight: isPopover ? 520 : 580,
            idealHeight: isPopover ? 580 : 660
        )
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            manager.refreshWindows()
        }
        .onDisappear {
            ScreenHighlightOverlay.shared.hideHoverPreview()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.indigo, Color.cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                Image(systemName: "pin.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(35))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("PinTop")
                        .font(.system(size: 18, weight: .bold))
                    if !manager.pinnedControllers.isEmpty {
                        Text("\(manager.pinnedControllers.count) Pinned")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.indigo))
                    }
                }
                Text("Keep Chrome or any macOS window always on top")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                manager.startInteractiveWindowPicker()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "scope")
                        .font(.system(size: 13, weight: .bold))
                    Text("Pick on Screen")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accentColor)
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .help("Click any window on screen to pin it (⌃⌥K)")

            Button {
                manager.refreshWindows()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.secondary.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh window list")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Permissions Banner

    private var permissionsBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 15))
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Optional macOS Permissions for Full Hybrid Power")
                    .font(.system(size: 11, weight: .semibold))
                Text("Hover & Pick work immediately. Enable Screen Recording for 60fps live overlay/PiP, and Accessibility to raise individual windows.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !manager.hasScreenRecordingPermission {
                Button {
                    manager.requestScreenRecordingPermission()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle")
                        Text("Screen Recording")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.2)))
                    .foregroundColor(.orange)
                }
                .buttonStyle(.plain)
            } else {
                Label("Screen OK", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            }

            if !manager.hasAccessibilityPermission {
                Button {
                    manager.requestAccessibilityPermission()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.point.up.left.fill")
                        Text("Accessibility")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.cyan.opacity(0.2)))
                    .foregroundColor(.cyan)
                }
                .buttonStyle(.plain)
            } else {
                Label("AX OK", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.orange.opacity(0.06))
    }

    private func statusToast(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .foregroundColor(.cyan)
            Text(text)
                .font(.system(size: 12, weight: .medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.cyan.opacity(0.10))
    }

    // MARK: - Pinned Windows Section

    private var pinnedWindowsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Currently Pinned on Top (\(manager.pinnedControllers.count))", systemImage: "pin.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                if manager.pinnedControllers.count > 1 {
                    Button("Unpin All") {
                        manager.unpinAll()
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.red)
                    .buttonStyle(.plain)
                }
            }

            ForEach(manager.pinnedControllers, id: \.windowID) { controller in
                PinnedWindowCardView(controller: controller)
            }
        }
    }

    // MARK: - Open Windows List Section

    private var openWindowsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Open Windows (\(manager.filteredWindows.count))", systemImage: "macwindow.on.rectangle")
                    .font(.system(size: 13, weight: .bold))

                Spacer()

                Button {
                    manager.filterBrowsersOnly.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                        Text("Chrome & Browsers Only")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(manager.filterBrowsersOnly ? Color.indigo : Color.secondary.opacity(0.14))
                    )
                    .foregroundColor(manager.filterBrowsersOnly ? .white : .primary)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter by app name, window title, or screen side (e.g. Chrome, Left Half)...", text: $manager.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !manager.searchQuery.isEmpty {
                    Button {
                        manager.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.10))
            )

            Text("💡 Tip: Hover over any window below to highlight its exact position on your screen.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            if manager.filteredWindows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No matching open windows found")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(manager.filteredWindows) { window in
                        WindowRowView(
                            window: window,
                            isPinned: manager.isPinned(window.id),
                            onPinMode: { mode in
                                manager.pinWindow(window, mode: mode)
                            },
                            onUnpin: {
                                manager.unpinWindow(windowID: window.id)
                            },
                            onFocus: {
                                WindowDiscovery.shared.raiseAndFocusWindow(
                                    windowID: window.id,
                                    pid: window.pid,
                                    targetBounds: window.quartzBounds
                                )
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 14) {
            shortcutBadge(keys: "⌃⌥P", label: "Pin Active")
            shortcutBadge(keys: "⌃⌥K", label: "Pick Window")
            shortcutBadge(keys: "⌃⌥G", label: "Ghost Mode")
            shortcutBadge(keys: "⌃⌥U", label: "Unpin All")

            Spacer()

            Button("Quit PinTop") {
                NSApp.terminate(nil)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.05))
    }

    private func shortcutBadge(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.18)))
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Pinned Window Card View

private struct PinnedWindowCardView: View {
    @ObservedObject var controller: PinnedWindowController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if let icon = controller.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 20))
                        .frame(width: 28, height: 28)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(controller.displayTitle)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(controller.ownerName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Text("•")
                            .foregroundColor(.secondary)

                        Text(statusDescription)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(statusColor)
                    }
                }

                Spacer()

                Button {
                    controller.focusRealWindow()
                } label: {
                    Label("Focus", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .help("Bring the real underlying window to the front")

                Button {
                    controller.onRequestUnpin?(controller.windowID)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pin.slash.fill")
                        Text("Unpin")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.red.opacity(0.16)))
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                // Mode Selector
                HStack(spacing: 4) {
                    ForEach(PinMode.allCases) { mode in
                        Button {
                            controller.mode = mode
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode.iconName)
                                    .font(.system(size: 10))
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: controller.mode == mode ? .bold : .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(controller.mode == mode ? Color.indigo : Color.secondary.opacity(0.12))
                            )
                            .foregroundColor(controller.mode == mode ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .help(mode.subtitle)
                    }
                }

                Spacer()

                // Opacity Slider
                HStack(spacing: 6) {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Slider(value: $controller.opacity, in: 0.25...1.0)
                        .frame(width: 110)
                    Text("\(Int(controller.opacity * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.indigo.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.indigo.opacity(0.38), lineWidth: 1.5)
                )
        )
    }

    private var statusDescription: String {
        switch controller.mode {
        case .inPlace:
            return controller.isTargetObstructed ? "Floating Mirror Active (Click to Interact)" : "Native Window Uncovered & Interactive"
        case .ghost:
            return "Click-Through Ghost Overlay (\(Int(controller.opacity * 100))%)"
        case .pip:
            return "Floating Picture-in-Picture"
        case .autoRaise:
            return "Auto-Raising Real Window"
        }
    }

    private var statusColor: Color {
        switch controller.mode {
        case .inPlace:
            return controller.isTargetObstructed ? .cyan : .green
        case .ghost:
            return .purple
        case .pip:
            return .orange
        case .autoRaise:
            return .green
        }
    }
}

// MARK: - Open Window Row View

private struct WindowRowView: View {
    let window: WindowInfo
    let isPinned: Bool
    let onPinMode: (PinMode) -> Void
    let onUnpin: () -> Void
    let onFocus: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 20))
                    .frame(width: 30, height: 30)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(window.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if window.zOrderIndex == 0 {
                        Text("Frontmost")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.2)))
                            .foregroundColor(.green)
                    }
                }

                HStack(spacing: 8) {
                    Text(window.ownerName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(window.regionDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(window.sizeDescription)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isPinned {
                Button(action: onFocus) {
                    Text("Focus")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.14)))
                }
                .buttonStyle(.plain)

                Button(action: onUnpin) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Pinned (Unpin)")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.indigo))
                    .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 6) {
                    Button {
                        onPinMode(.inPlace)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pin.fill")
                            Text("Pin 1:1")
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.indigo))
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .help("Pin window in-place on top of other apps")

                    Button {
                        onPinMode(.ghost)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "eye.fill")
                            Text("Ghost")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .help("Pin as click-through translucent overlay")

                    Button {
                        onPinMode(.pip)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pip.fill")
                            Text("PiP")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .help("Open resizable floating Picture-in-Picture clone")

                    Button {
                        onPinMode(.autoRaise)
                    } label: {
                        Image(systemName: "arrow.up.forward.app.fill")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .help("Auto-Raise mode: keeps real window raised without screen capture")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? Color.accentColor.opacity(0.09) : Color.secondary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isHovered ? Color.cyan.opacity(0.65) : Color.clear, lineWidth: 1.5)
                )
        )
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                ScreenHighlightOverlay.shared.showHoverPreview(for: window)
            } else {
                ScreenHighlightOverlay.shared.hideHoverPreview()
            }
        }
    }
}
