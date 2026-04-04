import Combine
import Foundation
import PortiCore
import AppKit

struct StoredProfile: Identifiable {
    let id: UUID
    let url: URL
    var profile: DockProfile

    init(url: URL, profile: DockProfile) {
        self.id = profile.id
        self.url = url
        self.profile = profile
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var profiles: [StoredProfile] = []
    @Published var activeProfileLabel = "Unknown"
    @Published var lastAppliedProfileName: String?
    @Published var warningMessage: String?
    @Published var errorMessage: String?
    @Published var confirmBeforeApply: Bool
    @Published var quitOtherApplicationsOnApply: Bool
    @Published var showNotifications: Bool
    @Published var launchAtLogin: Bool
    @Published private(set) var activeFocusProfileName: String?
    @Published private(set) var windowStatePermissionStatus: WindowStatePermissionStatus

    let dockStore = DockPreferencesStore()
    let profileStore = ProfileStore()
    private let defaults = UserDefaults.standard
    private let lastAppliedProfilePathKey = "porti.lastAppliedProfilePath"
    private let profileOrderKey = "porti.profileOrder"
    private let confirmBeforeApplyKey = "porti.preferences.confirmBeforeApply"
    private let quitOtherApplicationsOnApplyKey = "porti.preferences.quitOtherApplicationsOnApply"
    private let showNotificationsKey = "porti.preferences.showNotifications"
    private let launchAtLoginKey = "porti.preferences.launchAtLogin"
    private let launchAtLoginController = LaunchAtLoginController()
    private let notificationController = NotificationController()
    private let windowStateController = WindowStateController()
    private var refreshTimer: Timer?
    private var lastObservedFocusProfileID: String?
    private var focusSelectionRefreshInFlight = false

    init() {
        let defaultPreferences = AppPreferences.default
        confirmBeforeApply = defaults.object(forKey: confirmBeforeApplyKey) as? Bool ?? defaultPreferences.confirmBeforeApply
        quitOtherApplicationsOnApply = defaults.object(forKey: quitOtherApplicationsOnApplyKey) as? Bool ?? defaultPreferences.quitOtherApplicationsOnApply
        showNotifications = defaults.object(forKey: showNotificationsKey) as? Bool ?? defaultPreferences.showNotifications
        launchAtLogin = defaults.object(forKey: launchAtLoginKey) as? Bool ?? launchAtLoginController.currentStatus()
        windowStatePermissionStatus = windowStateController.permissionStatus()
        refreshAll()
        startRefreshTimer()
    }

    func refreshAll() {
        windowStatePermissionStatus = windowStateController.permissionStatus()

        do {
            let loadedProfiles = try profileStore.listProfiles().map { url in
                StoredProfile(url: url, profile: try profileStore.load(from: url))
            }
            profiles = orderedProfiles(from: loadedProfiles)

            try refreshActiveState()
            refreshFocusSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveCurrentDock(named name: String) {
        do {
            let profile = try dockStore.captureCurrentProfile(named: name)
            let savedURL = try profileStore.save(profile)
            defaults.set(savedURL.path, forKey: lastAppliedProfilePathKey)
            showFeedback(
                inlineWarning: nil,
                inlineError: nil,
                notificationTitle: "Profile Saved",
                notificationBody: "Saved \(profile.name)."
            )
            refreshAll()
        } catch {
            presentError(error)
        }
    }

    func promptAndSaveCurrentDock() {
        let hadVisibleMainWindow = NSApplication.shared.windows.contains {
            $0.isVisible && $0.canBecomeMain && !($0 is NSPanel)
        }
        let suggestedName = PortNameCatalog.randomDisplayName()

        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Save Current Dock"
        alert.informativeText = "Choose a name for this Dock profile."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        textField.placeholderString = suggestedName
        alert.accessoryView = textField
        let alertWindow = alert.window
        alertWindow.initialFirstResponder = textField
        center(window: alertWindow)
        alertWindow.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            self.center(window: alertWindow)
            alertWindow.makeFirstResponder(textField)
        }

        let response = alert.runModal()
        if !hadVisibleMainWindow {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
        guard response == .alertFirstButtonReturn else {
            return
        }

        let enteredName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        saveCurrentDock(named: enteredName.isEmpty ? suggestedName : enteredName)
    }

    func apply(_ storedProfile: StoredProfile) {
        apply(storedProfile, trigger: .manual)
    }

    func addSpacerToCurrentDock() {
        do {
            try dockStore.addSpacerToCurrentDock()
            showFeedback(
                inlineWarning: nil,
                inlineError: nil,
                notificationTitle: "Spacer Added",
                notificationBody: "Added a spacer to the end of the Dock app section."
            )
            refreshAll()
        } catch {
            presentError(error)
        }
    }

    func updateLastAppliedProfileFromCurrentDock() {
        guard activeProfileLabel == "Custom" else {
            return
        }

        do {
            guard let lastAppliedURL = try lastAppliedProfileURL() else {
                throw PortiAppError("There is no last applied profile to update.")
            }

            let existing = try profileStore.load(from: lastAppliedURL)
            let captured = try dockStore.captureCurrentProfile(named: existing.name)
            _ = try profileStore.overwriteProfile(at: lastAppliedURL, with: captured)
            showFeedback(
                inlineWarning: nil,
                inlineError: nil,
                notificationTitle: "Profile Updated",
                notificationBody: "Updated \(existing.name) from the current Dock."
            )
            refreshAll()
        } catch {
            presentError(error)
        }
    }

    func delete(_ storedProfile: StoredProfile) {
        do {
            try profileStore.deleteProfile(at: storedProfile.url)
            if defaults.string(forKey: lastAppliedProfilePathKey) == storedProfile.url.path {
                defaults.removeObject(forKey: lastAppliedProfilePathKey)
            }
            removeProfileFromOrder(storedProfile)
            showFeedback(
                inlineWarning: nil,
                inlineError: nil,
                notificationTitle: "Profile Deleted",
                notificationBody: "Deleted \(storedProfile.profile.name)."
            )
            refreshAll()
        } catch {
            presentError(error)
        }
    }

    func duplicate(_ storedProfile: StoredProfile) {
        do {
            let duplicatedURL = try profileStore.duplicateProfile(at: storedProfile.url)
            let duplicatedProfile = try profileStore.load(from: duplicatedURL)
            appendProfileToOrder(duplicatedProfile.id)
            showFeedback(
                inlineWarning: nil,
                inlineError: nil,
                notificationTitle: "Profile Duplicated",
                notificationBody: "Duplicated \(storedProfile.profile.name)."
            )
            refreshAll()
        } catch {
            presentError(error)
        }
    }

    func moveProfile(id draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID,
              let sourceIndex = profiles.firstIndex(where: { $0.id == draggedID }) else {
            return
        }

        var reordered = profiles
        let moved = reordered.remove(at: sourceIndex)
        guard let targetIndex = reordered.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        reordered.insert(moved, at: targetIndex)
        profiles = reordered
        defaults.set(reordered.map { $0.id.uuidString }, forKey: profileOrderKey)
    }

    func moveProfile(id draggedID: UUID, after targetID: UUID) {
        guard draggedID != targetID,
              let sourceIndex = profiles.firstIndex(where: { $0.id == draggedID }) else {
            return
        }

        var reordered = profiles
        let moved = reordered.remove(at: sourceIndex)
        guard let targetIndex = reordered.firstIndex(where: { $0.id == targetID }) else {
            return
        }
        reordered.insert(moved, at: targetIndex + 1)
        profiles = reordered
        defaults.set(reordered.map { $0.id.uuidString }, forKey: profileOrderKey)
    }

    func moveProfileToEnd(id draggedID: UUID) {
        guard let sourceIndex = profiles.firstIndex(where: { $0.id == draggedID }) else {
            return
        }

        var reordered = profiles
        let moved = reordered.remove(at: sourceIndex)
        reordered.append(moved)
        profiles = reordered
        defaults.set(reordered.map { $0.id.uuidString }, forKey: profileOrderKey)
    }

    func rename(_ storedProfile: StoredProfile, to name: String, notify: Bool = true) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }

        guard trimmed != storedProfile.profile.name else {
            return
        }

        do {
            let newURL = try profileStore.renameProfile(at: storedProfile.url, to: trimmed)
            if defaults.string(forKey: lastAppliedProfilePathKey) == storedProfile.url.path {
                defaults.set(newURL.path, forKey: lastAppliedProfilePathKey)
            }
            if notify {
                showFeedback(
                    inlineWarning: nil,
                    inlineError: nil,
                    notificationTitle: "Profile Renamed",
                    notificationBody: "Renamed \(storedProfile.profile.name) to \(trimmed)."
                )
            } else {
                warningMessage = nil
                errorMessage = nil
            }
            refreshAll()
        } catch {
            presentError(error)
        }
    }

    func overwriteWithCurrentDock(_ storedProfile: StoredProfile) {
        do {
            let captured = try dockStore.captureCurrentProfile(named: storedProfile.profile.name)
            _ = try profileStore.overwriteProfile(at: storedProfile.url, with: captured)
            showFeedback(
                inlineWarning: nil,
                inlineError: nil,
                notificationTitle: "Profile Updated",
                notificationBody: "Updated \(storedProfile.profile.name) from the current Dock."
            )
            refreshAll()
        } catch {
            presentError(error)
        }
    }

    func clearMessages() {
        warningMessage = nil
        errorMessage = nil
    }

    func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAtLoginController.setEnabled(enabled)
            launchAtLogin = enabled
            defaults.set(enabled, forKey: launchAtLoginKey)
            showFeedback(
                inlineWarning: nil,
                inlineError: nil,
                notificationTitle: enabled ? "Launch At Login Enabled" : "Launch At Login Disabled",
                notificationBody: enabled ? "Porti will try to launch at login." : "Porti will no longer launch at login."
            )
        } catch {
            launchAtLogin = launchAtLoginController.currentStatus()
            defaults.set(launchAtLogin, forKey: launchAtLoginKey)
            presentError(error)
        }
    }

    func setConfirmBeforeApply(_ enabled: Bool) {
        confirmBeforeApply = enabled
        defaults.set(confirmBeforeApply, forKey: confirmBeforeApplyKey)
    }

    func setQuitOtherApplicationsOnApply(_ enabled: Bool) {
        quitOtherApplicationsOnApply = enabled
        defaults.set(quitOtherApplicationsOnApply, forKey: quitOtherApplicationsOnApplyKey)
    }

    func setShowNotifications(_ enabled: Bool) {
        showNotifications = enabled
        defaults.set(showNotifications, forKey: showNotificationsKey)
    }

    func requestWindowStateAccessibilityPermission() {
        windowStatePermissionStatus = windowStateController.requestAccessibilityPermission()
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func apply(_ storedProfile: StoredProfile, trigger: DockApplyTrigger) {
        if trigger.requiresConfirmation,
           confirmBeforeApply,
           !confirmApply(named: storedProfile.profile.name) {
            return
        }

        let windowStateSnapshot = windowStateController.captureCurrentWindowStates()

        do {
            let report = try dockStore.apply(profile: storedProfile.profile)
            let quitReport = quitOtherApplicationsOnApply ? requestQuitForApplicationsNotInProfile(storedProfile.profile) : QuitRequestReport()
            scheduleWindowStateRestore(windowStateSnapshot)
            defaults.set(storedProfile.url.path, forKey: lastAppliedProfilePathKey)
            showFeedback(
                inlineWarning: warningText(for: report, quitReport: quitReport),
                inlineError: nil,
                notificationTitle: notificationTitle(for: report, quitReport: quitReport, trigger: trigger),
                notificationBody: notificationText(
                    forAppliedProfile: storedProfile.profile.name,
                    report: report,
                    quitReport: quitReport,
                    trigger: trigger
                )
            )
            try refreshActiveState()
        } catch {
            presentError(error)
        }
    }

    private func refreshActiveState() throws {
        guard let path = defaults.string(forKey: lastAppliedProfilePathKey) else {
            activeProfileLabel = "Unknown"
            lastAppliedProfileName = nil
            return
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            defaults.removeObject(forKey: lastAppliedProfilePathKey)
            activeProfileLabel = "Unknown"
            lastAppliedProfileName = nil
            return
        }

        let profile = try profileStore.load(from: url)
        lastAppliedProfileName = profile.name
        switch try dockStore.state(relativeTo: profile) {
        case .active:
            activeProfileLabel = profile.name
        case .custom:
            activeProfileLabel = "Custom"
        }
    }

    private func lastAppliedProfileURL() throws -> URL? {
        guard let path = defaults.string(forKey: lastAppliedProfilePathKey) else {
            return nil
        }

        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            defaults.removeObject(forKey: lastAppliedProfilePathKey)
            lastAppliedProfileName = nil
            return nil
        }

        return url
    }

    private func orderedProfiles(from loadedProfiles: [StoredProfile]) -> [StoredProfile] {
        let storedOrder = defaults.stringArray(forKey: profileOrderKey) ?? []
        let positionByID = Dictionary(uniqueKeysWithValues: storedOrder.enumerated().map { ($1, $0) })

        let ordered = loadedProfiles.sorted { lhs, rhs in
            let lhsPosition = positionByID[lhs.id.uuidString]
            let rhsPosition = positionByID[rhs.id.uuidString]

            switch (lhsPosition, rhsPosition) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return lhs.profile.name.localizedCaseInsensitiveCompare(rhs.profile.name) == .orderedAscending
            }
        }

        defaults.set(ordered.map { $0.id.uuidString }, forKey: profileOrderKey)
        return ordered
    }

    private func appendProfileToOrder(_ id: UUID) {
        var order = defaults.stringArray(forKey: profileOrderKey) ?? []
        let idString = id.uuidString
        guard !order.contains(idString) else {
            return
        }
        order.append(idString)
        defaults.set(order, forKey: profileOrderKey)
    }

    private func removeProfileFromOrder(_ storedProfile: StoredProfile) {
        let filtered = (defaults.stringArray(forKey: profileOrderKey) ?? []).filter { $0 != storedProfile.id.uuidString }
        defaults.set(filtered, forKey: profileOrderKey)
    }

    private func center(window: NSWindow) {
        let activeScreen = NSScreen.screens.first {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        } ?? NSScreen.main

        guard let screen = activeScreen else {
            window.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let targetCenterY = visibleFrame.maxY - (visibleFrame.height / 3)
        let origin = NSPoint(
            x: visibleFrame.midX - (window.frame.width / 2),
            y: targetCenterY - (window.frame.height / 2)
        )
        window.setFrameOrigin(origin)
    }

    private func warningText(for report: DockApplyReport, quitReport: QuitRequestReport) -> String? {
        var parts: [String] = []

        if !report.skippedItems.isEmpty {
            let names = report.skippedItems.map { $0.label ?? $0.path ?? "Unnamed item" }
            parts.append("Skipped missing items: \(names.joined(separator: ", "))")
        }

        if !quitReport.requestedApplications.isEmpty {
            parts.append("Asked to quit: \(quitReport.requestedApplications.joined(separator: ", "))")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func notificationTitle(for report: DockApplyReport, quitReport: QuitRequestReport, trigger: DockApplyTrigger) -> String {
        if !report.skippedItems.isEmpty {
            return trigger == .focusMode ? "Focus Mode Applied With Skips" : "Profile Applied With Skips"
        }

        if !quitReport.requestedApplications.isEmpty {
            return trigger == .focusMode ? "Focus Mode Applied And Closing Apps" : "Profile Applied And Closing Apps"
        }

        return trigger == .focusMode ? "Focus Mode Applied" : "Profile Applied"
    }

    private func notificationText(
        forAppliedProfile name: String,
        report: DockApplyReport,
        quitReport: QuitRequestReport,
        trigger: DockApplyTrigger
    ) -> String {
        var parts = [trigger == .focusMode ? "Applied \(name) for the active Focus mode." : "Applied \(name)."]

        if !report.skippedItems.isEmpty {
            let names = report.skippedItems.map { $0.label ?? $0.path ?? "Unnamed item" }
            parts.append("Skipped missing items: \(names.joined(separator: ", ")).")
        }

        if !quitReport.requestedApplications.isEmpty {
            parts.append("Asked these apps to quit: \(quitReport.requestedApplications.joined(separator: ", ")).")
        }

        return parts.joined(separator: " ")
    }

    private func refreshFocusSelection() {
        guard !focusSelectionRefreshInFlight else {
            return
        }

        focusSelectionRefreshInFlight = true

        Task { [weak self] in
            let selection = await PortiFocusSelectionResolver.currentSelection()

            await MainActor.run {
                guard let self else {
                    return
                }

                self.focusSelectionRefreshInFlight = false
                self.handleFocusSelection(selection)
            }
        }
    }

    private func handleFocusSelection(_ selection: PortiFocusSelection?) {
        activeFocusProfileName = selection?.profileName

        let selectedProfileID = selection?.profileID
        guard selectedProfileID != lastObservedFocusProfileID else {
            return
        }
        lastObservedFocusProfileID = selectedProfileID

        guard let selectedProfileID,
              let storedProfile = profiles.first(where: { $0.id.uuidString == selectedProfileID }) else {
            return
        }

        do {
            if try dockStore.state(relativeTo: storedProfile.profile) == .active {
                defaults.set(storedProfile.url.path, forKey: lastAppliedProfilePathKey)
                try refreshActiveState()
                return
            }
        } catch {
            presentError(error)
            return
        }

        apply(storedProfile, trigger: .focusMode)
    }

    private func showFeedback(
        inlineWarning: String?,
        inlineError: String?,
        notificationTitle: String,
        notificationBody: String
    ) {
        warningMessage = inlineWarning
        errorMessage = inlineError

        if showNotifications {
            notificationController.send(title: notificationTitle, body: notificationBody)
        }
    }

    private func presentError(_ error: Error) {
        warningMessage = nil
        errorMessage = error.localizedDescription

        if showNotifications {
            notificationController.send(title: "Porti Error", body: error.localizedDescription)
        }
    }

    private func confirmApply(named name: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Apply \(name)?"
        alert.informativeText = "This will replace your current Dock profile."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func requestQuitForApplicationsNotInProfile(_ profile: DockProfile) -> QuitRequestReport {
        let targetBundleIdentifiers: Set<String> = Set(profile.applications.compactMap { tile in
            guard tile.kind == .app else {
                return nil
            }
            return tile.bundleIdentifier?.lowercased()
        })
        let targetPaths: Set<String> = Set(profile.applications.compactMap { tile in
            guard tile.kind == .app, let path = tile.path else {
                return nil
            }
            return URL(fileURLWithPath: path).resolvingSymlinksInPath().path.lowercased()
        })
        let ownBundleIdentifier = Bundle.main.bundleIdentifier?.lowercased()
        let ownProcessIdentifier = ProcessInfo.processInfo.processIdentifier

        let requestedApplications = NSWorkspace.shared.runningApplications.compactMap { application -> String? in
            guard application.activationPolicy == .regular,
                  !application.isTerminated,
                  application.processIdentifier != ownProcessIdentifier else {
                return nil
            }

            let bundleIdentifier = application.bundleIdentifier?.lowercased()
            if bundleIdentifier == ownBundleIdentifier || bundleIdentifier == "com.apple.finder" {
                return nil
            }

            let normalizedPath = application.bundleURL?.resolvingSymlinksInPath().path.lowercased()
            if let bundleIdentifier, targetBundleIdentifiers.contains(bundleIdentifier) {
                return nil
            }
            if let normalizedPath, targetPaths.contains(normalizedPath) {
                return nil
            }

            guard application.terminate() else {
                return nil
            }

            return application.localizedName
                ?? application.bundleURL?.deletingPathExtension().lastPathComponent
                ?? application.bundleIdentifier
        }

        return QuitRequestReport(requestedApplications: requestedApplications.sorted())
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAll()
            }
        }
        refreshTimer?.tolerance = 0.5
    }

    private func scheduleWindowStateRestore(_ snapshot: WindowStateSnapshot?) {
        guard snapshot != nil else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { [weak self] in
            self?.windowStateController.restoreWindowStates(snapshot)
        }
    }
}

private struct QuitRequestReport {
    let requestedApplications: [String]

    init(requestedApplications: [String] = []) {
        self.requestedApplications = requestedApplications
    }
}

private enum DockApplyTrigger {
    case manual
    case focusMode

    var requiresConfirmation: Bool {
        switch self {
        case .manual:
            return true
        case .focusMode:
            return false
        }
    }
}
