import SwiftUI
import UniformTypeIdentifiers

struct ProfileManagerView: View {
    @ObservedObject var appState: AppState
    var showsSaveButton: Bool = true
    @State private var draggedProfileID: UUID?
    @State private var dropIndicator: ProfileDropIndicator?
    @State private var listContentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsSaveButton {
                Button("Save Current Dock...") {
                    appState.promptAndSaveCurrentDock()
                }
                .keyboardShortcut(.defaultAction)

                Divider()
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(appState.profiles.enumerated()), id: \.element.id) { index, storedProfile in
                        VStack(alignment: .leading, spacing: 0) {
                            ProfileManagerRowView(
                                appState: appState,
                                storedProfile: storedProfile,
                                draggedProfileID: $draggedProfileID,
                                dropIndicator: $dropIndicator
                            )

                            if index < appState.profiles.count - 1 {
                                Divider()
                                    .padding(.leading, 28)
                            }
                        }
                    }

                    ZStack {
                        Color.clear
                            .frame(height: 18)

                        if dropIndicator == .end {
                            InsertionIndicator()
                                .padding(.leading, 34)
                        }
                    }
                        .onDrop(
                            of: [UTType.text],
                            delegate: ProfileDropToEndDelegate(
                                appState: appState,
                                draggedProfileID: $draggedProfileID,
                                dropIndicator: $dropIndicator
                            )
                        )
                }
                .padding(.vertical, 4)
                .animation(.spring(response: 0.24, dampingFraction: 0.88), value: appState.profiles.map(\.id))
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: ProfileListHeightPreferenceKey.self, value: proxy.size.height)
                    }
                }
            }
            .frame(height: max(listContentHeight, 120))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onPreferenceChange(ProfileListHeightPreferenceKey.self) { newHeight in
            listContentHeight = newHeight
        }
    }
}

private struct ProfileListHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 120

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ProfileManagerRowView: View {
    @ObservedObject var appState: AppState
    let storedProfile: StoredProfile
    @Binding var draggedProfileID: UUID?
    @Binding var dropIndicator: ProfileDropIndicator?

    @State private var renameDraft: String
    @State private var pendingRenameTask: DispatchWorkItem?
    @State private var rowHeight: CGFloat = 0
    @FocusState private var isNameFieldFocused: Bool

    init(
        appState: AppState,
        storedProfile: StoredProfile,
        draggedProfileID: Binding<UUID?>,
        dropIndicator: Binding<ProfileDropIndicator?>
    ) {
        self.appState = appState
        self.storedProfile = storedProfile
        _draggedProfileID = draggedProfileID
        _dropIndicator = dropIndicator
        _renameDraft = State(initialValue: storedProfile.profile.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                dragHandle

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 8) {
                        TextField("Profile name", text: $renameDraft)
                            .textFieldStyle(.roundedBorder)
                            .focused($isNameFieldFocused)
                            .onSubmit {
                                commitRename()
                            }
                            .frame(minWidth: 140, idealWidth: 180, maxWidth: .infinity)

                        Button("Apply") {
                            appState.apply(storedProfile)
                        }
                        Button("Duplicate") {
                            appState.duplicate(storedProfile)
                        }
                        Button("Override") {
                            appState.overwriteWithCurrentDock(storedProfile)
                        }
                        Button("Delete", role: .destructive) {
                            appState.delete(storedProfile)
                        }
                    }
                    .buttonStyle(.bordered)

                    Text("\(storedProfile.profile.applications.count) apps, \(storedProfile.profile.others.count) others")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .allowsHitTesting(false)
                    .onAppear {
                        rowHeight = proxy.size.height
                    }
                    .onChange(of: proxy.size.height) { newValue in
                        rowHeight = newValue
                    }
            }
        }
        .overlay(alignment: .top) {
            if dropIndicator == .before(storedProfile.id) {
                InsertionIndicator()
                    .padding(.leading, 34)
                    .offset(y: -7)
            }
        }
        .overlay(alignment: .bottom) {
            if dropIndicator == .after(storedProfile.id) {
                InsertionIndicator()
                    .padding(.leading, 34)
                    .offset(y: 7)
            }
        }
        .opacity(draggedProfileID == storedProfile.id ? 0.58 : 1)
        .scaleEffect(draggedProfileID == storedProfile.id ? 0.985 : 1)
        .onDrop(
            of: [UTType.text],
            delegate: ProfileDropDelegate(
                targetProfileID: storedProfile.id,
                rowHeight: rowHeight,
                appState: appState,
                draggedProfileID: $draggedProfileID,
                dropIndicator: $dropIndicator
            )
        )
        .onChange(of: storedProfile.profile.name) { newValue in
            renameDraft = newValue
        }
        .onChange(of: renameDraft) { newValue in
            scheduleRename(for: newValue)
        }
        .onChange(of: isNameFieldFocused) { isFocused in
            if !isFocused {
                commitRename()
            }
        }
        .onDisappear {
            pendingRenameTask?.cancel()
        }
    }

    private func scheduleRename(for newValue: String) {
        pendingRenameTask?.cancel()

        let task = DispatchWorkItem {
            commitRename()
        }

        pendingRenameTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: task)
    }

    private func commitRename() {
        pendingRenameTask?.cancel()
        pendingRenameTask = nil
        appState.rename(storedProfile, to: renameDraft, notify: false)
    }

    private var dragHandle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.12))

            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 3) {
                        Circle().frame(width: 2, height: 2)
                        Circle().frame(width: 2, height: 2)
                    }
                }
            }
            .foregroundStyle(.secondary)
        }
        .frame(width: 14, height: 20)
        .contentShape(Rectangle())
        .help("Drag to reorder")
        .onDrag {
            draggedProfileID = storedProfile.id
            dropIndicator = nil
            return NSItemProvider(object: storedProfile.id.uuidString as NSString)
        } preview: {
            DragPreviewRow(title: renameDraft.isEmpty ? storedProfile.profile.name : renameDraft)
        }
    }
}

private struct ProfileDropDelegate: DropDelegate {
    let targetProfileID: UUID
    let rowHeight: CGFloat
    let appState: AppState
    @Binding var draggedProfileID: UUID?
    @Binding var dropIndicator: ProfileDropIndicator?

    func dropEntered(info: DropInfo) {
        updateDropIndicator(using: info)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let activeDraggedProfileID = draggedProfileID,
              let resolvedIndicator = resolvedIndicator(using: info) else {
            return false
        }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            switch resolvedIndicator {
            case .before:
                appState.moveProfile(id: activeDraggedProfileID, before: targetProfileID)
            case .after:
                appState.moveProfile(id: activeDraggedProfileID, after: targetProfileID)
            }
        }
        draggedProfileID = nil
        dropIndicator = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateDropIndicator(using: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropIndicator == .before(targetProfileID) || dropIndicator == .after(targetProfileID) {
            dropIndicator = nil
        }
    }

    private func updateDropIndicator(using info: DropInfo) {
        switch resolvedIndicator(using: info) {
        case .before:
            dropIndicator = .before(targetProfileID)
        case .after:
            dropIndicator = .after(targetProfileID)
        case nil:
            dropIndicator = nil
        }
    }

    private func resolvedIndicator(using info: DropInfo) -> TargetInsertion? {
        guard let draggedProfileID, draggedProfileID != targetProfileID else {
            return nil
        }

        let midpoint = max(rowHeight, 1) / 2
        return info.location.y < midpoint ? .before : .after
    }
}

private enum TargetInsertion {
    case before
    case after
}

private struct ProfileDropToEndDelegate: DropDelegate {
    let appState: AppState
    @Binding var draggedProfileID: UUID?
    @Binding var dropIndicator: ProfileDropIndicator?

    func dropEntered(info: DropInfo) {
        guard draggedProfileID != nil else {
            return
        }
        dropIndicator = .end
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let activeDraggedProfileID = draggedProfileID else {
            return false
        }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            appState.moveProfileToEnd(id: activeDraggedProfileID)
        }
        self.draggedProfileID = nil
        self.dropIndicator = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropIndicator == .end {
            dropIndicator = nil
        }
    }
}

private enum ProfileDropIndicator: Equatable {
    case before(UUID)
    case after(UUID)
    case end
}

private struct InsertionIndicator: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.accentColor.opacity(0.95))
            .frame(height: 3)
            .shadow(color: Color.accentColor.opacity(0.18), radius: 4, y: 1)
    }
}

private struct DragPreviewRow: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.stack")
                .foregroundStyle(.secondary)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 280)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
