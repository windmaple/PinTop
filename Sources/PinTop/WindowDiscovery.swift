import Cocoa
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

@MainActor
public final class WindowDiscovery {
    public static let shared = WindowDiscovery()

    private let ignoredOwnerNames: Set<String> = [
        "WindowServer",
        "Dock",
        "Control Center",
        "Notification Center",
        "SystemUIServer",
        "Spotlight",
        "Wallpaper",
        "TextInputMenuAgent",
        "TextInputSwitcher",
        "CursorUIViewService",
        "universalAccessAuthWarn"
    ]

    private init() {}

    /// Discovers all normal on-screen application windows in front-to-back Z-order.
    public func discoverWindows(pinnedIDs: Set<CGWindowID> = []) -> [WindowInfo] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // Cache AX window titles per PID if Accessibility is trusted
        var axTitlesByPID: [pid_t: [CGWindowID: String]] = [:]
        let isAXTrusted = AXIsProcessTrusted()

        // Cache running applications by PID for icons
        var runningAppsByPID: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications {
            runningAppsByPID[app.processIdentifier] = app
        }

        var results: [WindowInfo] = []
        var zIndex = 0
        var regionCountsByOwner: [String: Int] = [:]

        for entry in rawList {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else {
                continue
            }
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != myPID else {
                continue
            }
            guard let wid = entry[kCGWindowNumber as String] as? CGWindowID, wid > 0 else {
                continue
            }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0.05 else { continue }

            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? "Application"
            if ignoredOwnerNames.contains(ownerName) {
                continue
            }

            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }

            // Exclude tiny status bubbles (like Chrome's 22px URL status bar) or invisible helper windows
            if bounds.width < 120 || bounds.height < 80 {
                continue
            }

            var title = (entry[kCGWindowName as String] as? String) ?? ""
            if title.isEmpty && isAXTrusted {
                if axTitlesByPID[pid] == nil {
                    axTitlesByPID[pid] = fetchAXWindowTitles(for: pid)
                }
                if let axTitle = axTitlesByPID[pid]?[wid], !axTitle.isEmpty {
                    title = axTitle
                }
            }

            let baseRegion = describeScreenRegion(for: bounds)
            let ownerRegionKey = "\(ownerName)|\(baseRegion)"
            let count = (regionCountsByOwner[ownerRegionKey] ?? 0) + 1
            regionCountsByOwner[ownerRegionKey] = count
            let regionDesc = count == 1 ? baseRegion : "\(baseRegion) #\(count)"

            let icon = runningAppsByPID[pid]?.icon

            let info = WindowInfo(
                id: wid,
                pid: pid,
                ownerName: ownerName,
                windowTitle: title,
                quartzBounds: bounds,
                zOrderIndex: zIndex,
                appIcon: icon,
                regionDescription: regionDesc
            )
            results.append(info)
            zIndex += 1
        }

        return results
    }

    /// Queries exact bounds and obstruction state for a specific CGWindowID.
    public func queryLiveWindowState(windowID: CGWindowID) -> (exists: Bool, isOnScreen: Bool, quartzBounds: CGRect?, title: String?, isObstructed: Bool) {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let onScreenOptions: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawList = CGWindowListCopyWindowInfo(onScreenOptions, kCGNullWindowID) as? [[String: Any]] else {
            return (false, false, nil, nil, false)
        }

        var frontWindowBounds: [CGRect] = []
        for entry in rawList {
            guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != myPID else { continue }
            guard let wid = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0.05 else { continue }
            let ownerName = entry[kCGWindowOwnerName as String] as? String ?? ""
            if ignoredOwnerNames.contains(ownerName) { continue }

            guard let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else {
                continue
            }
            if bounds.width < 120 || bounds.height < 80 { continue }

            if wid == windowID {
                let title = entry[kCGWindowName as String] as? String
                // Check if any normal window in front of this window significantly overlaps it
                let isObstructed = frontWindowBounds.contains { frontRect in
                    let intersection = frontRect.intersection(bounds)
                    return !intersection.isNull && intersection.width > 14 && intersection.height > 14
                }
                return (true, true, bounds, title, isObstructed)
            } else {
                frontWindowBounds.append(bounds)
            }
        }

        // Check if the window still exists off-screen / minimized
        if let allList = CGWindowListCopyWindowInfo([.optionAll], windowID) as? [[String: Any]],
           let match = allList.first(where: { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }) {
            var bounds: CGRect?
            if let boundsDict = match[kCGWindowBounds as String] as? NSDictionary {
                bounds = CGRect(dictionaryRepresentation: boundsDict)
            }
            let title = match[kCGWindowName as String] as? String
            return (true, false, bounds, title, true)
        }

        return (false, false, nil, nil, false)
    }

    /// Finds the topmost normal window under a given Cocoa screen point.
    public func windowAtScreenPoint(_ cocoaPoint: NSPoint, excludingWindowIDs: Set<CGWindowID> = []) -> WindowInfo? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1440
        let quartzPoint = CGPoint(x: cocoaPoint.x, y: primaryHeight - cocoaPoint.y)
        let windows = discoverWindows()
        return windows.first { win in
            !excludingWindowIDs.contains(win.id) && win.quartzBounds.contains(quartzPoint)
        }
    }

    /// Returns the frontmost candidate window to pin (used by the global hotkey ⌃⌥P).
    public func frontmostCandidateWindow() -> WindowInfo? {
        let windows = discoverWindows()
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           frontApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            if let match = windows.first(where: { $0.pid == frontApp.processIdentifier }) {
                return match
            }
        }
        return windows.first
    }

    /// Brings a specific window to the front and activates its application.
    public func raiseAndFocusWindow(windowID: CGWindowID, pid: pid_t, targetBounds: CGRect? = nil) {
        if AXIsProcessTrusted() {
            let appElement = AXUIElementCreateApplication(pid)
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
               let axWindows = value as? [AXUIElement] {
                var matchedElement: AXUIElement?
                for axWin in axWindows {
                    var wid: CGWindowID = 0
                    if _AXUIElementGetWindow(axWin, &wid) == .success && wid == windowID {
                        matchedElement = axWin
                        break
                    }
                }
                if matchedElement == nil, let targetBounds = targetBounds {
                    matchedElement = axWindows.first { axWin in
                        guard let frame = getAXWindowFrame(axWin) else { return false }
                        return abs(frame.origin.x - targetBounds.origin.x) < 10 &&
                               abs(frame.origin.y - targetBounds.origin.y) < 10
                    }
                }
                if let axWin = matchedElement {
                    AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
                    AXUIElementSetAttributeValue(axWin, kAXMainAttribute as CFString, kCFBooleanTrue)
                    AXUIElementSetAttributeValue(axWin, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                    AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                }
            }
        }

        if let app = NSRunningApplication(processIdentifier: pid) {
            app.activate()
        }
    }

    /// Raises a window via AXRaise without stealing focus if possible, or activates if needed.
    public func performAXRaiseOnly(windowID: CGWindowID, pid: pid_t) {
        guard AXIsProcessTrusted() else { return }
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else { return }
        for axWin in axWindows {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(axWin, &wid) == .success && wid == windowID {
                AXUIElementPerformAction(axWin, kAXRaiseAction as CFString)
                break
            }
        }
    }

    private func fetchAXWindowTitles(for pid: pid_t) -> [CGWindowID: String] {
        var map: [CGWindowID: String] = [:]
        let appElement = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else {
            return map
        }
        for axWin in axWindows {
            var wid: CGWindowID = 0
            if _AXUIElementGetWindow(axWin, &wid) == .success && wid > 0 {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let title = titleRef as? String, !title.isEmpty {
                    map[wid] = title
                }
            }
        }
        return map
    }

    private func getAXWindowFrame(_ axWin: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef) == .success else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        if let posVal = posRef, CFGetTypeID(posVal) == AXValueGetTypeID() {
            AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        }
        if let sizeVal = sizeRef, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: point, size: size)
    }

    private func describeScreenRegion(for quartzBounds: CGRect) -> String {
        let screenW = NSScreen.screens.first?.frame.width ?? 2498
        let screenH = NSScreen.screens.first?.frame.height ?? 1440

        let wRatio = quartzBounds.width / screenW
        let hRatio = quartzBounds.height / screenH
        let centerX = quartzBounds.midX / screenW

        if wRatio > 0.85 && hRatio > 0.85 {
            return "Full Screen"
        } else if wRatio >= 0.42 && wRatio <= 0.58 && hRatio > 0.75 {
            if centerX < 0.45 {
                return "Left Half"
            } else if centerX > 0.55 {
                return "Right Half"
            }
        }
        if centerX < 0.4 {
            return "Left (\(Int(quartzBounds.width))×\(Int(quartzBounds.height)))"
        } else if centerX > 0.6 {
            return "Right (\(Int(quartzBounds.width))×\(Int(quartzBounds.height)))"
        } else {
            return "Center (\(Int(quartzBounds.width))×\(Int(quartzBounds.height)))"
        }
    }
}
