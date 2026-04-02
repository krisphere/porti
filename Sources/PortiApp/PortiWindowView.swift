import SwiftUI

enum PortiWindowTab: String, CaseIterable, Identifiable {
    case profiles
    case settings
    case about

    static let defaultHeight: CGFloat = 580
    static let settingsContentHeight: CGFloat = 400
    static let settingsWindowHeight: CGFloat = 400
    static let aboutWindowHeight: CGFloat = 150
    static let profilesButtonGap: CGFloat = 20
    static let profilesButtonRowHeight: CGFloat = 32
    static let profilesBottomPadding: CGFloat = 20

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

    var preferredHeight: CGFloat {
        switch self {
        case .settings:
            return Self.settingsWindowHeight
        case .about:
            return Self.aboutWindowHeight
        case .profiles:
            return Self.defaultHeight
        }
    }
}

@MainActor
struct PortiPreferencesView: View {
    private static let resizeDuration: Double = 0.22

    @ObservedObject var appState: AppState
    @ObservedObject var appUpdater: AppUpdater
    @ObservedObject var selection: PreferencesSelection

    @State private var contentWidth: CGFloat = PortiWindowTab.profiles.preferredWidth
    @State private var contentHeight: CGFloat = PortiWindowTab.profiles.preferredHeight
    @State private var isPaneContentVisible = true
    @State private var pendingRevealWorkItem: DispatchWorkItem?
    @State private var windowResizeRevision = 0
    @State private var shouldAnimateWindowResize = false

    var body: some View {
        tabViewContent
    }

    private func updateLayout(for tab: PortiWindowTab, animate: Bool) {
        let targetHeight: CGFloat = switch tab {
        case .profiles:
            Self.profilesWindowHeight(forProfileCount: appState.profiles.count)
        case .settings, .about:
            tab.preferredHeight
        }

        shouldAnimateWindowResize = animate
        windowResizeRevision += 1

        let change = {
            contentWidth = tab.preferredWidth
            contentHeight = targetHeight
        }

        if animate {
            withAnimation(.easeInOut(duration: Self.resizeDuration)) {
                change()
            }
        } else {
            change()
        }
    }

    private static func profilesWindowHeight(forProfileCount count: Int) -> CGFloat {
        ProfileManagerView.listHeight(forProfileCount: count)
            + PortiWindowTab.profilesButtonGap
            + PortiWindowTab.profilesButtonRowHeight
            + PortiWindowTab.profilesBottomPadding
    }

    private func beginTabTransition(to tab: PortiWindowTab) {
        pendingRevealWorkItem?.cancel()

        isPaneContentVisible = false
        updateLayout(for: tab, animate: true)

        let revealWorkItem = DispatchWorkItem {
            isPaneContentVisible = true
            pendingRevealWorkItem = nil
        }

        pendingRevealWorkItem = revealWorkItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.resizeDuration, execute: revealWorkItem)
    }

    private var tabViewContent: some View {
        TabView(selection: $selection.tab) {
            PreferencesPaneContainer(
                showsContent: isPaneContentVisible,
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
                showsContent: isPaneContentVisible,
                warningMessage: appState.warningMessage,
                errorMessage: appState.errorMessage,
                clearMessages: appState.clearMessages
            ) {
                SettingsView(appState: appState, appUpdater: appUpdater)
                    .frame(height: PortiWindowTab.settingsContentHeight, alignment: .topLeading)
            }
            .tabItem {
                Label(PortiWindowTab.settings.title, systemImage: PortiWindowTab.settings.systemImage)
            }
            .tag(PortiWindowTab.settings)

            PreferencesPaneContainer(
                showsContent: isPaneContentVisible,
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
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
        .frame(width: contentWidth, height: contentHeight)
        .background(
            WindowConfigurator(
                contentWidth: contentWidth,
                contentHeight: contentHeight,
                animateResize: shouldAnimateWindowResize,
                resizeDuration: Self.resizeDuration,
                resizeRevision: windowResizeRevision
            )
        )
        .onAppear {
            appState.refreshAll()
            updateLayout(for: selection.tab, animate: false)
            isPaneContentVisible = true
        }
        .onChange(of: selection.tab) { newValue in
            beginTabTransition(to: newValue)
        }
        .onChange(of: appState.profiles.map(\.id)) { _ in
            guard selection.tab == .profiles else {
                return
            }
            updateLayout(for: .profiles, animate: true)
        }
    }
}

private struct PreferencesPaneContainer<Content: View>: View {
    let showsContent: Bool
    let warningMessage: String?
    let errorMessage: String?
    let clearMessages: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
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
        .opacity(showsContent ? 1 : 0)
        .allowsHitTesting(showsContent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ProfilesPreferencesPane: View {
    private static let contentSpacing: CGFloat = PortiWindowTab.profilesButtonGap

    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Self.contentSpacing) {
            ProfileManagerView(appState: appState, showsSaveButton: false)

            HStack {
                Spacer()

                Button("Save Current Dock") {
                    appState.promptAndSaveCurrentDock()
                }
                .buttonStyle(.bordered)
            }
            .padding(.trailing, 20)
        }
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

private struct WindowConfigurator: NSViewRepresentable {
    let contentWidth: CGFloat
    let contentHeight: CGFloat
    let animateResize: Bool
    let resizeDuration: Double
    let resizeRevision: Int

    final class Coordinator {
        var lastAppliedRevision = -1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configureWindow(for: view, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configureWindow(for: nsView, coordinator: context.coordinator)
        }
    }

    private func configureWindow(for view: NSView, coordinator: Coordinator) {
        guard let window = view.window else {
            return
        }

        window.title = "Porti"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .preference

        guard coordinator.lastAppliedRevision != resizeRevision else {
            return
        }

        coordinator.lastAppliedRevision = resizeRevision
        applyWindowSize(to: window)
    }

    private func applyWindowSize(to window: NSWindow) {
        let targetContentSize = NSSize(width: contentWidth, height: contentHeight)
        let currentContentSize = window.contentLayoutRect.size
        guard abs(currentContentSize.width - targetContentSize.width) > 0.5 ||
                abs(currentContentSize.height - targetContentSize.height) > 0.5 else {
            return
        }

        let currentFrame = window.frame
        let targetFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: targetContentSize))

        var newFrame = currentFrame
        newFrame.origin.y += currentFrame.height - targetFrame.height
        newFrame.size = targetFrame.size

        if animateResize {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = resizeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(newFrame, display: true)
            }
        } else {
            window.setFrame(newFrame, display: true)
        }
    }
}
