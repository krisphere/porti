import SwiftUI

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var appUpdater: AppUpdater

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSectionCard("Apply Behavior") {
                Toggle(
                    "Confirm before applying a profile",
                    isOn: Binding(
                        get: { appState.confirmBeforeApply },
                        set: { appState.setConfirmBeforeApply($0) }
                    )
                )

                VStack(alignment: .leading, spacing: 6) {
                    Toggle(
                        "Quit other applications when switching docks",
                        isOn: Binding(
                            get: { appState.quitOtherApplicationsOnApply },
                            set: { appState.setQuitOtherApplicationsOnApply($0) }
                        )
                    )
                    
                    SettingsCaption("Porti will only ask apps that are not in the target Dock profile to quit normally. Apps can still keep running if you cancel their save prompts.")
                        .padding(.leading, 22)
                }

                Toggle(
                    "Show notifications",
                    isOn: Binding(
                        get: { appState.showNotifications },
                        set: { appState.setShowNotifications($0) }
                    )
                )
            }

            Divider()

            SettingsSectionCard("Window Restore") {
                HStack(alignment: .center, spacing: 10) {
                    Text("Accessibility access")
                        .font(.system(size: 13, weight: .medium))

                    PermissionStatusBadge(status: appState.windowStatePermissionStatus)
                }

                switch appState.windowStatePermissionStatus {
                case .granted:
                    SettingsCaption("Window restore is enabled for apps that stay open after a Dock switch.")
                case .notRequested:
                    SettingsCaption("Grant Accessibility access to enable window restore after Dock switches.")
                case .denied:
                    SettingsCaption("Window restore is unavailable because Accessibility access is not enabled.")
                }

                HStack(spacing: 10) {
                    Button("Request Access") {
                        appState.requestWindowStateAccessibilityPermission()
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.windowStatePermissionStatus == .granted)

                    Button("Open Accessibility Settings") {
                        appState.openAccessibilitySettings()
                    }
                    .buttonStyle(.bordered)
                    .disabled(appState.windowStatePermissionStatus == .granted)
                }
            }

            Divider()

            SettingsSectionCard("Focus Mode") {
                Text("Assign Porti profiles from macOS Focus settings to switch Dock layouts automatically.")
                    .font(.body)

                SettingsCaption("Set this up in System Settings > Focus > a Focus mode > Focus Filters > Porti, then choose the Dock profile for that Focus.")

                if let activeFocusProfileName = appState.activeFocusProfileName {
                    SettingsCaption("Current Porti Focus profile: \(activeFocusProfileName)")
                } else {
                    SettingsCaption("No Porti Focus filter is active right now.")
                }

                SettingsCaption("Automatic Focus-driven switching only works while Porti is running. Enable Launch at login if you want it available after sign-in.")
            }

            Divider()

            SettingsSectionCard(
                "Updates",
                headerAccessory: {
                    Button("Check for Updates") {
                        appUpdater.checkForUpdates()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!appUpdater.isConfigured || !appUpdater.canCheckForUpdates)
                }
            ) {
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

            }

            Divider()

            SettingsSectionCard("System") {
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { appState.launchAtLogin },
                        set: { appState.updateLaunchAtLogin($0) }
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let headerAccessory: () -> AnyView
    @ViewBuilder let content: () -> Content

    init(
        _ title: String,
        @ViewBuilder headerAccessory: @escaping () -> some View = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.headerAccessory = { AnyView(headerAccessory()) }
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                headerAccessory()
            }

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

private struct PermissionStatusBadge: View {
    let status: WindowStatePermissionStatus

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
    }

    private var label: String {
        switch status {
        case .granted:
            return "Granted"
        case .notRequested:
            return "Not Requested"
        case .denied:
            return "Not Granted"
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .granted:
            return Color(nsColor: .systemGreen)
        case .notRequested:
            return Color(nsColor: .systemOrange)
        case .denied:
            return Color(nsColor: .systemRed)
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .granted:
            return Color(nsColor: .systemGreen).opacity(0.14)
        case .notRequested:
            return Color(nsColor: .systemOrange).opacity(0.14)
        case .denied:
            return Color(nsColor: .systemRed).opacity(0.14)
        }
    }
}
