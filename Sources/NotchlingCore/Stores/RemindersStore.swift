import Foundation

/// The to-do list state the UI binds to. Two-way synced with a `RemindersProviding`.
@MainActor
public final class RemindersStore: ObservableObject {
    @Published public private(set) var items: [Todo] = []
    @Published public private(set) var lists: [ReminderList] = []
    @Published public private(set) var access: RemindersAccess
    @Published public private(set) var lastError: String?
    /// Text in the "add a reminder" field.
    @Published public var draft = ""

    /// Which Reminders list to show. `nil` = the default list.
    public var listID: String? {
        didSet { if listID != oldValue { Task { await reload() } } }
    }

    private let provider: RemindersProviding
    private let completionDelay: Duration
    private var pendingCompletions: [String: Task<Void, Never>] = [:]

    /// - Parameter completionDelay: how long a ticked row stays visible (and can be un-ticked)
    ///   before it's marked complete in Reminders.
    public init(provider: RemindersProviding, listID: String? = nil,
                completionDelay: Duration = .milliseconds(1200)) {
        self.provider = provider
        self.listID = listID
        self.completionDelay = completionDelay
        self.access = provider.authorizationStatus()
        provider.observeChanges { [weak self] in
            Task { @MainActor in await self?.reload() }
        }
    }

    public var openCount: Int { items.filter { !$0.isDone }.count }

    public func requestAccess() async {
        access = await provider.requestAccess() ? .granted : .denied
        await reload()
    }

    public func reload() async {
        guard access == .granted else { return }
        lists = provider.lists()
        do {
            let fetched = try await provider.incompleteReminders(in: listID)
            // Rows mid-"tick" stay put until their completion lands, so they don't vanish early.
            let ticking = items.filter { pendingCompletions[$0.id] != nil }
            let tickingIDs = Set(ticking.map(\.id))
            items = ticking + ReminderOrdering.sorted(fetched.filter { !tickingIDs.contains($0.id) })
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func addDraft() async {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, access == .granted else { return }
        do {
            try provider.add(title: title, to: listID)
            draft = ""
            await reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Ticking shows a check right away and commits after `completionDelay`.
    /// Ticking the same row again within that window cancels it.
    public func toggle(_ todo: Todo) {
        guard let index = items.firstIndex(where: { $0.id == todo.id }) else { return }
        if let pending = pendingCompletions.removeValue(forKey: todo.id) {
            pending.cancel()
            items[index].isDone = false
            return
        }
        items[index].isDone = true
        let delay = completionDelay
        pendingCompletions[todo.id] = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.commitCompletion(of: todo.id)
        }
    }

    private func commitCompletion(of id: String) {
        pendingCompletions[id] = nil
        do {
            try provider.complete(id: id)
            items.removeAll { $0.id == id }
        } catch {
            if let index = items.firstIndex(where: { $0.id == id }) { items[index].isDone = false }
            lastError = error.localizedDescription
        }
    }

    /// Test hook: waits for every scheduled completion to finish.
    func settlePendingCompletions() async {
        for task in pendingCompletions.values { await task.value }
    }
}
