import Foundation

/// The notes scratchpad. Saved shortly after typing stops, not on every keystroke.
@MainActor
public final class NotesStore: ObservableObject {
    static let key = "notesText"
    public static let maxLength = 5_000

    @Published public var text: String {
        didSet {
            if text.count > Self.maxLength { text = String(text.prefix(Self.maxLength)); return }
            scheduleSave()
        }
    }

    private let defaults: UserDefaults
    private let saveDelay: Duration
    private var saveTask: Task<Void, Never>?

    public init(defaults: UserDefaults = .standard, saveDelay: Duration = .milliseconds(500)) {
        self.defaults = defaults
        self.saveDelay = saveDelay
        text = defaults.string(forKey: Self.key) ?? ""
    }

    /// Writes now, e.g. when the app quits.
    public func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        defaults.set(text, forKey: Self.key)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let delay = saveDelay
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Test hook.
    func settle() async { await saveTask?.value }
}
