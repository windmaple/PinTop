# PinTop — Always on Top Window Manager for macOS

**PinTop** is a native macOS app (Swift / AppKit / SwiftUI / ScreenCaptureKit) that lets you pin any window—such as Google Chrome—always on top of other applications without disabling System Integrity Protection (SIP).

## Features

- **4 Hybrid Pinning Modes** (switchable anytime via the floating top-right pill or dashboard):
  - **`1:1 Pin` (In-Place Interactive)**: Keeps the target window pinned in its exact position. When unobstructed, all clicks, scrolling, and typing pass straight to the native window; when overlapped by another app, a 60fps zero-copy `IOSurface` floating mirror stays on top, and clicking it brings the real window forward.
  - **`Ghost` (Click-Through)**: Translucent floating overlay with customizable opacity (`25%–100%`) that lets mouse clicks and scrolling pass directly to applications underneath.
  - **`PiP` (Picture-in-Picture)**: Movable, resizable floating mini-window of any target window.
  - **`Auto-Raise`**: Automatically raises the real window whenever another window overlaps it.
- **Interactive On-Screen Window Picker (`⌃⌥K`)**: Move your crosshair cursor over any window on screen to highlight and pin it with a single click.
- **Hover-to-Highlight Window List**: Hovering any window row in PinTop highlights that exact window on your physical screen.
- **Global Keyboard Shortcuts**:
  - `⌃⌥P` — Pin / Unpin active window
  - `⌃⌥K` — Pick window on screen
  - `⌃⌥G` — Toggle Ghost Click-Through mode
  - `⌃⌥U` — Unpin all windows

## Build & Run

```bash
chmod +x build_app.sh
./build_app.sh
open PinTop.app
```
