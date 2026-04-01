import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var preferencesSelection: PreferencesSelection

    var body: some View {
        Group {
            Text("Active: \(appState.activeProfileLabel)")

            if appState.profiles.isEmpty {
                Text("No saved profiles")
            } else {
                ForEach(appState.profiles) { storedProfile in
                    Button {
                        appState.apply(storedProfile)
                    } label: {
                        Label(
                            storedProfile.profile.name,
                            systemImage: storedProfile.profile.name == appState.activeProfileLabel ? "checkmark" : "dock.rectangle"
                        )
                    }

                    if appState.activeProfileLabel == "Custom",
                       appState.lastAppliedProfileName == storedProfile.profile.name {
                        Button {
                            appState.updateLastAppliedProfileFromCurrentDock()
                        } label: {
                            Text("Update \(storedProfile.profile.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            .padding(.leading, 14)
                        }
                    }
                }
            }

            Divider()

            Button {
                appState.promptAndSaveCurrentDock()
            } label: {
                Label("Save Current Dock...", systemImage: "plus.square.on.square")
            }
            .keyboardShortcut(.defaultAction)

            Button {
                appState.addSpacerToCurrentDock()
            } label: {
                Label("Add Spacer to Dock", systemImage: "space")
            }

            Button {
                openSettings(tab: .profiles)
            } label: {
                Label("Manage Profiles...", systemImage: "square.and.pencil")
            }

            Divider()

            Button {
                openSettings(tab: .settings)
            } label: {
                Label("Settings...", systemImage: "gearshape")
            }

            Button {
                appUpdater.checkForUpdates()
            } label: {
                Label("Check for Updates...", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!appUpdater.isConfigured || !appUpdater.canCheckForUpdates)

            Button {
                openSettings(tab: .about)
            } label: {
                Label("About Porti", systemImage: "info.circle")
            }

            if let warningMessage = appState.warningMessage {
                Divider()
                Label(warningMessage, systemImage: "exclamationmark.triangle")
            }

            if let errorMessage = appState.errorMessage {
                Divider()
                Label(errorMessage, systemImage: "xmark.octagon")
            }

            if appState.warningMessage != nil || appState.errorMessage != nil {
                Button {
                    appState.clearMessages()
                } label: {
                    Label("Clear Messages", systemImage: "xmark")
                }
            }

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Porti", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
        .onAppear {
            appState.refreshAll()
        }
    }

    private func openSettings(tab: PortiWindowTab) {
        preferencesSelection.tab = tab
        PortiSettingsPresenter.request(tab: tab)
    }
}
