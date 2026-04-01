import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var appUpdater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard("Apply Behavior") {
                Toggle(
                    "Confirm before applying a profile",
                    isOn: Binding(
                        get: { appState.confirmBeforeApply },
                        set: { appState.setConfirmBeforeApply($0) }
                    )
                )

                Toggle(
                    "Quit other applications when switching docks",
                    isOn: Binding(
                        get: { appState.quitOtherApplicationsOnApply },
                        set: { appState.setQuitOtherApplicationsOnApply($0) }
                    )
                )

                Toggle(
                    "Show notifications",
                    isOn: Binding(
                        get: { appState.showNotifications },
                        set: { appState.setShowNotifications($0) }
                    )
                )

                SettingsCaption("Porti will only ask apps that are not in the target Dock profile to quit normally. Apps can still keep running if you cancel their save prompts.")
            }

            SettingsSectionCard("Updates") {
                Toggle(
                    "Automatically check for updates",
                    isOn: Binding(
                        get: { appUpdater.automaticallyChecksForUpdates },
                        set: { appUpdater.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                .disabled(!appUpdater.isConfigured)

                Toggle(
                    "Automatically download updates",
                    isOn: Binding(
                        get: { appUpdater.automaticallyDownloadsUpdates },
                        set: { appUpdater.setAutomaticallyDownloadsUpdates($0) }
                    )
                )
                .disabled(!appUpdater.isConfigured || !appUpdater.automaticallyChecksForUpdates)

                HStack {
                    Spacer()

                    Button("Check for Updates...") {
                        appUpdater.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!appUpdater.isConfigured || !appUpdater.canCheckForUpdates)
                }

                if let configurationIssue = appUpdater.configurationIssue {
                    SettingsCaption(configurationIssue)
                } else {
                    SettingsCaption("Sparkle stores these updater preferences in the app’s defaults. Install Porti from an app bundle in Applications for the smoothest update flow.")
                }
            }

            SettingsSectionCard("System") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.updateLaunchAtLogin($0) }
                    )
                )

                SettingsCaption("Launch at login may fail for ad hoc or development builds that are not installed as a normal app bundle.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct SettingsCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
