import AppKit
import ApplicationServices
import Foundation

enum WindowStatePermissionStatus {
    case granted
    case notRequested
    case denied
}

struct WindowStateSnapshot: Sendable {
    let applications: [CapturedApplicationState]

    var isEmpty: Bool {
        applications.isEmpty
    }
}

struct CapturedApplicationState: Sendable {
    let bundleIdentifier: String
    let isHidden: Bool
    let windows: [CapturedWindowState]
}

struct CapturedWindowState: Sendable {
    let title: String?
    let frame: CGRect
    let isMinimized: Bool
}

@MainActor
final class WindowStateController {
    private let defaults = UserDefaults.standard
    private let accessibilityPromptedKey = "porti.permissions.promptedForWindowStateAccessibility"

    func permissionStatus() -> WindowStatePermissionStatus {
        if AXIsProcessTrusted() {
            return .granted
        }

        return defaults.bool(forKey: accessibilityPromptedKey) ? .denied : .notRequested
    }

    @discardableResult
    func requestAccessibilityPermission() -> WindowStatePermissionStatus {
        _ = promptForAccessibilityPermission()
        return permissionStatus()
    }

    func captureCurrentWindowStates() -> WindowStateSnapshot? {
        guard hasAccessibilityPermission() else {
            return nil
        }

        let applications = NSWorkspace.shared.runningApplications.compactMap { application in
            captureState(for: application)
        }

        guard !applications.isEmpty else {
            return nil
        }

        return WindowStateSnapshot(applications: applications)
    }

    func restoreWindowStates(_ snapshot: WindowStateSnapshot?) {
        guard let snapshot, !snapshot.isEmpty else {
            return
        }

        guard hasAccessibilityPermission() else {
            return
        }

        let runningApplications = currentRunningApplicationsByBundleIdentifier()

        for applicationState in snapshot.applications {
            guard let application = runningApplications[applicationState.bundleIdentifier] else {
                continue
            }

            restore(applicationState, to: application)
        }
    }

    private func currentRunningApplicationsByBundleIdentifier() -> [String: NSRunningApplication] {
        let runningApplications: [String: NSRunningApplication] = NSWorkspace.shared.runningApplications.reduce(into: [:]) { result, application in
            guard let bundleIdentifier = application.bundleIdentifier?.lowercased(),
                  application.activationPolicy == .regular,
                  !application.isTerminated else {
                return
            }

            result[bundleIdentifier] = application
        }
        return runningApplications
    }

    private func captureState(for application: NSRunningApplication) -> CapturedApplicationState? {
        guard application.activationPolicy == .regular,
              !application.isTerminated,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleIdentifier = application.bundleIdentifier?.lowercased() else {
            return nil
        }

        let windows = windowElements(for: application).compactMap(captureState(for:))
        guard application.isHidden || !windows.isEmpty else {
            return nil
        }

        return CapturedApplicationState(
            bundleIdentifier: bundleIdentifier,
            isHidden: application.isHidden,
            windows: windows
        )
    }

    private func captureState(for window: AXUIElement) -> CapturedWindowState? {
        guard let position = copyPointValue(from: window, attribute: kAXPositionAttribute),
              let size = copySizeValue(from: window, attribute: kAXSizeAttribute),
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        let title = copyStringValue(from: window, attribute: kAXTitleAttribute)
        let isMinimized = copyBoolValue(from: window, attribute: kAXMinimizedAttribute) ?? false

        return CapturedWindowState(
            title: normalizedTitle(title),
            frame: CGRect(origin: position, size: size),
            isMinimized: isMinimized
        )
    }

    private func restore(_ applicationState: CapturedApplicationState, to application: NSRunningApplication) {
        let hasMinimizedWindows = applicationState.windows.contains { $0.isMinimized }
        let shouldTemporarilyHide = hasMinimizedWindows && !application.isHidden

        if shouldTemporarilyHide {
            application.hide()
        } else if !applicationState.isHidden && application.isHidden {
            application.unhide()
        }

        let windows = windowElements(for: application)
        let matches = matchedWindows(saved: applicationState.windows, live: windows)
        for match in matches {
            restore(match.savedState, to: match.window)
        }

        if applicationState.isHidden && !application.isHidden {
            application.hide()
        } else if !applicationState.isHidden && application.isHidden {
            application.unhide()
        }
    }

    private func restore(_ windowState: CapturedWindowState, to window: AXUIElement) {
        if windowState.isMinimized {
            setBoolValue(true, on: window, attribute: kAXMinimizedAttribute)
            return
        }

        setBoolValue(false, on: window, attribute: kAXMinimizedAttribute)
        setPointValue(windowState.frame.origin, on: window, attribute: kAXPositionAttribute)
        setSizeValue(windowState.frame.size, on: window, attribute: kAXSizeAttribute)
    }

    private func matchedWindows(saved: [CapturedWindowState], live: [AXUIElement]) -> [(savedState: CapturedWindowState, window: AXUIElement)] {
        var liveStates = live.compactMap { window -> LiveWindowState? in
            guard let position = copyPointValue(from: window, attribute: kAXPositionAttribute),
                  let size = copySizeValue(from: window, attribute: kAXSizeAttribute),
                  size.width > 0,
                  size.height > 0 else {
                return nil
            }

            return LiveWindowState(
                title: normalizedTitle(copyStringValue(from: window, attribute: kAXTitleAttribute)),
                frame: CGRect(origin: position, size: size),
                window: window
            )
        }

        var matches: [(savedState: CapturedWindowState, window: AXUIElement)] = []
        for savedState in saved {
            if let title = savedState.title,
               let matchIndex = liveStates.firstIndex(where: { $0.title == title }) {
                let liveState = liveStates.remove(at: matchIndex)
                matches.append((savedState, liveState.window))
                continue
            }

            if let matchIndex = liveStates.firstIndex(where: { $0.frame.equalTo(savedState.frame) }) {
                let liveState = liveStates.remove(at: matchIndex)
                matches.append((savedState, liveState.window))
                continue
            }

            guard !liveStates.isEmpty else {
                continue
            }

            let liveState = liveStates.removeFirst()
            matches.append((savedState, liveState.window))
        }

        return matches
    }

    private func windowElements(for application: NSRunningApplication) -> [AXUIElement] {
        let element = AXUIElementCreateApplication(application.processIdentifier)
        guard let value = copyAttributeValue(from: element, attribute: kAXWindowsAttribute) else {
            return []
        }

        if let windows = value as? [AXUIElement] {
            return windows
        }

        if let windows = value as? [Any] {
            return windows.map { $0 as! AXUIElement }
        }

        return []
    }

    private func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    private func promptForAccessibilityPermission() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        defaults.set(true, forKey: accessibilityPromptedKey)
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func copyAttributeValue(from element: AXUIElement, attribute: String) -> Any? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }

        return value
    }

    private func copyStringValue(from element: AXUIElement, attribute: String) -> String? {
        copyAttributeValue(from: element, attribute: attribute) as? String
    }

    private func copyBoolValue(from element: AXUIElement, attribute: String) -> Bool? {
        if let value = copyAttributeValue(from: element, attribute: attribute) as? Bool {
            return value
        }

        if let value = copyAttributeValue(from: element, attribute: attribute) as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    private func copyPointValue(from element: AXUIElement, attribute: String) -> CGPoint? {
        guard let value = copyAttributeValue(from: element, attribute: attribute) else {
            return nil
        }

        return point(from: value)
    }

    private func copySizeValue(from element: AXUIElement, attribute: String) -> CGSize? {
        guard let value = copyAttributeValue(from: element, attribute: attribute) else {
            return nil
        }

        return size(from: value)
    }

    private func setBoolValue(_ value: Bool, on element: AXUIElement, attribute: String) {
        _ = AXUIElementSetAttributeValue(element, attribute as CFString, NSNumber(value: value))
    }

    private func setPointValue(_ value: CGPoint, on element: AXUIElement, attribute: String) {
        var point = value
        guard let axValue = AXValueCreate(.cgPoint, &point) else {
            return
        }

        _ = AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
    }

    private func setSizeValue(_ value: CGSize, on element: AXUIElement, attribute: String) {
        var size = value
        guard let axValue = AXValueCreate(.cgSize, &size) else {
            return
        }

        _ = AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
    }

    private func point(from value: Any) -> CGPoint? {
        let cfValue = value as CFTypeRef
        guard CFGetTypeID(cfValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = cfValue as! AXValue
        guard AXValueGetType(axValue) == .cgPoint else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(axValue, .cgPoint, &point) else {
            return nil
        }

        return point
    }

    private func size(from value: Any) -> CGSize? {
        let cfValue = value as CFTypeRef
        guard CFGetTypeID(cfValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = cfValue as! AXValue
        guard AXValueGetType(axValue) == .cgSize else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(axValue, .cgSize, &size) else {
            return nil
        }

        return size
    }

    private func normalizedTitle(_ title: String?) -> String? {
        guard let title else {
            return nil
        }

        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

private struct LiveWindowState {
    let title: String?
    let frame: CGRect
    let window: AXUIElement
}
