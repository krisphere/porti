import SwiftUI

enum PortiWindowTab: String, CaseIterable, Identifiable {
    case profiles
    case settings
    case about

    var id: Self { self }

    var title: String {
        switch self {
        case .profiles:
            return "Profiles"
        case .settings:
            return "Settings"
        case .about:
            return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .profiles:
            return "square.and.pencil"
        case .settings:
            return "gearshape"
        case .about:
            return "info.circle"
        }
    }

    var preferredWidth: CGFloat {
        600
    }
}

@MainActor
struct PortiPreferencesView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var selection: PreferencesSelection

    @State private var contentWidth: CGFloat = PortiWindowTab.profiles.preferredWidth
    @State private var contentHeight: CGFloat = 560
    @State private var measuredHeights: [PortiWindowTab: CGFloat] = [:]

    var body: some View {
        Group {
            if #available(macOS 15.0, *) {
                tabViewContent
                    .toolbar(removing: .title)
            } else {
                tabViewContent
            }
        }
    }

    private func updateLayout(for tab: PortiWindowTab, animate: Bool) {
        let measuredHeight = measuredHeights[tab] ?? 520
        let change = {
            contentWidth = tab.preferredWidth
            contentHeight = measuredHeight
        }

        if animate {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                change()
            }
        } else {
            change()
        }
    }

    private var tabViewContent: some View {
        TabView(selection: $selection.tab) {
            PreferencesPaneContainer(
                tab: .profiles,
                warningMessage: appState.warningMessage,
                errorMessage: appState.errorMessage,
                clearMessages: appState.clearMessages
            ) {
                ProfilesPreferencesPane(appState: appState)
            }
            .tabItem {
                Label(PortiWindowTab.profiles.title, systemImage: PortiWindowTab.profiles.systemImage)
            }
            .tag(PortiWindowTab.profiles)

            PreferencesPaneContainer(
                tab: .settings,
                warningMessage: appState.warningMessage,
                errorMessage: appState.errorMessage,
                clearMessages: appState.clearMessages
            ) {
                SettingsView(appState: appState, appUpdater: appUpdater)
            }
            .tabItem {
                Label(PortiWindowTab.settings.title, systemImage: PortiWindowTab.settings.systemImage)
            }
            .tag(PortiWindowTab.settings)

            PreferencesPaneContainer(
                tab: .about,
                warningMessage: appState.warningMessage,
                errorMessage: appState.errorMessage,
                clearMessages: appState.clearMessages
            ) {
                AboutView()
            }
            .tabItem {
                Label(PortiWindowTab.about.title, systemImage: PortiWindowTab.about.systemImage)
            }
            .tag(PortiWindowTab.about)
        }
        .padding(20)
        .frame(width: contentWidth, height: contentHeight)
        .background(WindowConfigurator())
        .onAppear {
            appState.refreshAll()
            updateLayout(for: selection.tab, animate: false)
        }
        .onChange(of: selection.tab) { newValue in
            updateLayout(for: newValue, animate: true)
        }
        .onPreferenceChange(PreferencesPaneHeightPreferenceKey.self) { heights in
            measuredHeights.merge(heights) { _, new in new }
            updateLayout(for: selection.tab, animate: true)
        }
    }
}

private struct PreferencesPaneContainer<Content: View>: View {
    let tab: PortiWindowTab
    let warningMessage: String?
    let errorMessage: String?
    let clearMessages: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.bottom, 20)

            if warningMessage != nil || errorMessage != nil {
                WindowMessageBanner(
                    warningMessage: warningMessage,
                    errorMessage: errorMessage,
                    clearMessages: clearMessages
                )
                .padding(.bottom, 20)
            }

            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: PreferencesPaneHeightPreferenceKey.self,
                        value: [tab: proxy.size.height]
                    )
            }
        }
    }
}

private struct ProfilesPreferencesPane: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ProfileManagerView(appState: appState, showsSaveButton: false)

            HStack {
                Spacer()

                Button("Save Current Dock...") {
                    appState.promptAndSaveCurrentDock()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct WindowMessageBanner: View {
    let warningMessage: String?
    let errorMessage: String?
    let clearMessages: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: errorMessage == nil ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                .foregroundStyle(errorMessage == nil ? .yellow : .red)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                if let warningMessage {
                    Text(warningMessage)
                }

                if let errorMessage {
                    Text(errorMessage)
                }
            }
            .font(.callout)

            Spacer()

            Button("Clear") {
                clearMessages()
            }
            .buttonStyle(.link)
        }
        .padding(20)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct PreferencesPaneHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [PortiWindowTab: CGFloat] = [:]

    static func reduce(value: inout [PortiWindowTab: CGFloat], nextValue: () -> [PortiWindowTab: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView)
        }
    }

    private func configureWindow(for view: NSView) {
        guard let window = view.window else {
            return
        }

        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }
}
