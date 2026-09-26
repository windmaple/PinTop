import Cocoa

public enum PinMode: String, CaseIterable, Identifiable {
    case inPlace = "1:1 Pin"
    case ghost = "Ghost"
    case pip = "PiP"
    case autoRaise = "Auto-Raise"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .inPlace: return "pin.fill"
        case .ghost: return "eye.fill"
        case .pip: return "pip.fill"
        case .autoRaise: return "arrow.up.forward.app.fill"
        }
    }

    public var subtitle: String {
        switch self {
        case .inPlace:
            return "Keeps window on top in-place; click to interact natively"
        case .ghost:
            return "Click-through translucent overlay; interact with apps behind it"
        case .pip:
            return "Draggable, resizable floating Picture-in-Picture clone"
        case .autoRaise:
            return "Automatically brings the real window forward when covered"
        }
    }
}

public struct WindowInfo: Identifiable, Equatable {
    public let id: CGWindowID
    public let pid: pid_t
    public let ownerName: String
    public let windowTitle: String
    public let quartzBounds: CGRect
    public let zOrderIndex: Int
    public let appIcon: NSImage?
    public let regionDescription: String

    public var displayTitle: String {
        let trimmed = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != ownerName {
            return trimmed
        }
        return "\(ownerName) — \(regionDescription)"
    }

    public var sizeDescription: String {
        "\(Int(quartzBounds.width))×\(Int(quartzBounds.height))"
    }

    public var isChromeOrBrowser: Bool {
        let lower = ownerName.lowercased()
        return lower.contains("chrome") || lower.contains("safari") || lower.contains("arc") || lower.contains("firefox") || lower.contains("brave") || lower.contains("edge")
    }

    public var cocoaFrame: NSRect {
        Self.quartzToCocoa(quartzBounds)
    }

    public static func quartzToCocoa(_ quartzRect: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1440
        let cocoaY = primaryHeight - quartzRect.origin.y - quartzRect.size.height
        return NSRect(
            x: quartzRect.origin.x,
            y: cocoaY,
            width: quartzRect.size.width,
            height: quartzRect.size.height
        )
    }

    public static func cocoaToQuartz(_ cocoaRect: NSRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1440
        let quartzY = primaryHeight - cocoaRect.origin.y - cocoaRect.size.height
        return CGRect(
            x: cocoaRect.origin.x,
            y: quartzY,
            width: cocoaRect.size.width,
            height: cocoaRect.size.height
        )
    }

    public static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.pid == rhs.pid &&
        lhs.ownerName == rhs.ownerName &&
        lhs.windowTitle == rhs.windowTitle &&
        lhs.quartzBounds == rhs.quartzBounds &&
        lhs.zOrderIndex == rhs.zOrderIndex
    }
}
