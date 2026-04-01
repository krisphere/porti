import Foundation

@MainActor
final class PreferencesSelection: ObservableObject {
    @Published var tab: PortiWindowTab = .profiles
}

extension Notification.Name {
    static let portiOpenSettings = Notification.Name("portiOpenSettings")
}
