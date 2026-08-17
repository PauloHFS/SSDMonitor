# 0001. Dynamic Status Item Visibility and Auto-Start on Login

- **Status**: Accepted
- **Date**: 2026-08-17

## Context
Users requested that the application automatically appear in the macOS menu bar when the target SSD (`PauloSSDExterno`) is connected, and automatically hide its menu bar icon when the drive is ejected, avoiding menu bar clutter when the SSD is not in use. Additionally, to ensure seamless detection upon system startup, the application needs to run in the background as a login item.

## Decision
1. **Dynamic Status Item Visibility**: Keep the application running in background when the target volume is unmounted/ejected, setting `NSStatusItem.isVisible = false`. Upon detecting a mount event for the Target Volume, toggle `NSStatusItem.isVisible = true` and update telemetry metrics immediately.
2. **System Auto-Start**: Integrate `ServiceManagement.SMAppService.mainApp` to allow users to toggle automatic launch at macOS login directly from the application's menu.
3. **User Notifications**: Dispatch native macOS notifications via `UNUserNotificationCenter` when the Target Volume is mounted, safely ejected, or when launching in background without an attached Target Volume.

## Consequences
- Reduces macOS menu bar clutter when external SSDs are disconnected.
- Near-zero idle CPU and memory consumption while waiting for mount events in background.
- Requires macOS notification permissions for system alert delivery.
