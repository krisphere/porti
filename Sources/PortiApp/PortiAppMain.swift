import AppKit
import SwiftUI

@main
struct PortiAppMain: App {
    @StateObject private var appState: AppState
    @StateObject private var appUpdater: AppUpdater
    @StateObject private var preferencesSelection: PreferencesSelection

    init() {
        let appState = AppState()
        let appUpdater = AppUpdater()
        let preferencesSelection = PreferencesSelection()

        _appState = StateObject(wrappedValue: appState)
        _appUpdater = StateObject(wrappedValue: appUpdater)
        _preferencesSelection = StateObject(wrappedValue: preferencesSelection)

        if let bundledIconImage = AppMetadata.bundledIconImage {
            NSApplication.shared.applicationIconImage = bundledIconImage
        }
    }

    @SceneBuilder
    var body: some Scene {
        WindowGroup("PortiLifecycleKeepalive") {
            HiddenWindowView(selection: preferencesSelection)
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

        Settings {
            PortiPreferencesView(
                appState: appState,
                appUpdater: appUpdater,
                selection: preferencesSelection
            )
        }
        .defaultSize(
            width: PortiWindowTab.profiles.preferredWidth,
            height: 560
        )
        .windowResizability(.contentSize)

        MenuBarExtra("Porti", systemImage: "dock.rectangle") {
            MenuBarContentView(
                appState: appState,
                appUpdater: appUpdater,
                preferencesSelection: preferencesSelection
            )
        }
        .menuBarExtraStyle(.menu)
    }
}
