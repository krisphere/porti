import AppKit
import SwiftUI

struct HiddenWindowView: View {
    @ObservedObject var selection: PreferencesSelection

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsBridgeView(selection: selection)
            } else {
                LegacySettingsBridgeView(selection: selection)
            }
        }
    }
}

@available(macOS 14.0, *)
private struct SettingsBridgeView: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var selection: PreferencesSelection

    var body: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .onReceive(NotificationCenter.default.publisher(for: .portiOpenSettings)) { notification in
                if let rawValue = notification.userInfo?["tab"] as? String,
                   let tab = PortiWindowTab(rawValue: rawValue) {
                    selection.tab = tab
                }

                Task { @MainActor in
                    openSettings()
                }
            }
            .onAppear {
                hideKeepaliveWindow()
                runLaunchWindowTestIfNeeded()
            }
    }

    private func hideKeepaliveWindow() {
        guard let window = NSApp.windows.first(where: { $0.title == "PortiLifecycleKeepalive" }) else {
            return
        }

        window.styleMask = [.borderless]
        window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
        window.isExcludedFromWindowsMenu = true
        window.level = .floating
        window.isOpaque = false
        window.alphaValue = 0
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.setContentSize(NSSize(width: 1, height: 1))
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
    }

    private func runLaunchWindowTestIfNeeded() {
        guard let requestedTabName = ProcessInfo.processInfo.environment["PORTI_OPEN_WINDOW_ON_LAUNCH"],
              let requestedTab = PortiWindowTab(rawValue: requestedTabName.lowercased()) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            selection.tab = requestedTab
            Task { @MainActor in
                openSettings()
            }

            if ProcessInfo.processInfo.environment["PORTI_CYCLE_TABS_FOR_TEST"] == "1" {
                cycleTabsForLaunchTest(startingWith: requestedTab)
            }
        }
    }

    private func cycleTabsForLaunchTest(startingWith initialTab: PortiWindowTab) {
        let tabs = PortiWindowTab.allCases
        guard let initialIndex = tabs.firstIndex(of: initialTab) else {
            return
        }

        for offset in 1..<tabs.count {
            let tab = tabs[(initialIndex + offset) % tabs.count]
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(offset) * 1.0)) {
                selection.tab = tab
            }
        }
    }
}

private struct LegacySettingsBridgeView: View {
    @ObservedObject var selection: PreferencesSelection

    var body: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .onReceive(NotificationCenter.default.publisher(for: .portiOpenSettings)) { notification in
                if let rawValue = notification.userInfo?["tab"] as? String,
                   let tab = PortiWindowTab(rawValue: rawValue) {
                    selection.tab = tab
                }

                PortiSettingsPresenter.showFallback()
            }
            .onAppear {
                hideKeepaliveWindow()
                runLaunchWindowTestIfNeeded()
            }
    }

    private func hideKeepaliveWindow() {
        guard let window = NSApp.windows.first(where: { $0.title == "PortiLifecycleKeepalive" }) else {
            return
        }

        window.styleMask = [.borderless]
        window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
        window.isExcludedFromWindowsMenu = true
        window.level = .floating
        window.isOpaque = false
        window.alphaValue = 0
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.canHide = false
        window.setContentSize(NSSize(width: 1, height: 1))
        window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
    }

    private func runLaunchWindowTestIfNeeded() {
        guard let requestedTabName = ProcessInfo.processInfo.environment["PORTI_OPEN_WINDOW_ON_LAUNCH"],
              let requestedTab = PortiWindowTab(rawValue: requestedTabName.lowercased()) else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            selection.tab = requestedTab
            PortiSettingsPresenter.showFallback()

            if ProcessInfo.processInfo.environment["PORTI_CYCLE_TABS_FOR_TEST"] == "1" {
                cycleTabsForLaunchTest(startingWith: requestedTab)
            }
        }
    }

    private func cycleTabsForLaunchTest(startingWith initialTab: PortiWindowTab) {
        let tabs = PortiWindowTab.allCases
        guard let initialIndex = tabs.firstIndex(of: initialTab) else {
            return
        }

        for offset in 1..<tabs.count {
            let tab = tabs[(initialIndex + offset) % tabs.count]
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(offset) * 1.0)) {
                selection.tab = tab
            }
        }
    }
}

enum PortiSettingsPresenter {
    @MainActor
    static func request(tab: PortiWindowTab) {
        NotificationCenter.default.post(
            name: .portiOpenSettings,
            object: nil,
            userInfo: ["tab": tab.rawValue]
        )
    }

    @MainActor
    static func showFallback() {
        NSApp.activate(ignoringOtherApps: true)

        let settingsSelector = Selector(("showSettingsWindow:"))
        if NSApp.sendAction(settingsSelector, to: nil, from: nil) {
            return
        }

        let preferencesSelector = Selector(("showPreferencesWindow:"))
        _ = NSApp.sendAction(preferencesSelector, to: nil, from: nil)
    }
}
