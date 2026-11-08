import Foundation
@testable import NotchlingCore

/// In-memory stand-in for Apple Reminders. `@unchecked Sendable` is fine here:
/// tests drive it from the main actor only.
final class FakeRemindersProvider: RemindersProviding, @unchecked Sendable {
    var access: RemindersAccess = .granted
    var grantOnRequest = true
    var reminderLists = [ReminderList(id: "home", title: "Home"), ReminderList(id: "work", title: "Work")]
    var reminders: [String: [Todo]] = [:]   // listID ("" = default) -> items
    var completedIDs: [String] = []
    var failNextComplete = false
    var failFetch = false
    private var onChange: (@Sendable () -> Void)?

    func authorizationStatus() -> RemindersAccess { access }

    func requestAccess() async -> Bool {
        access = grantOnRequest ? .granted : .denied
        return grantOnRequest
    }

    func lists() -> [ReminderList] { reminderLists }

    func incompleteReminders(in listID: String?) async throws -> [Todo] {
        if failFetch { throw RemindersError.noList }
        return reminders[listID ?? "", default: []]
    }

    func add(title: String, to listID: String?) throws {
        reminders[listID ?? "", default: []].append(Todo(id: UUID().uuidString, title: title, created: Date()))
    }

    func complete(id: String) throws {
        if failNextComplete {
            failNextComplete = false
            throw RemindersError.notFound
        }
        completedIDs.append(id)
        for key in reminders.keys { reminders[key]?.removeAll { $0.id == id } }
    }

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }

    /// Simulates an edit made in the Reminders app or on another device.
    func simulateExternalChange() { onChange?() }
}

struct FakeLoginItem: LoginItemManaging {
    var isEnabled = false
    var error: Error?

    func setEnabled(_ enabled: Bool) throws {
        if let error { throw error }
    }
}

struct FakeError: LocalizedError {
    var errorDescription: String? { "Not allowed" }
}

/// A fresh, isolated UserDefaults per test so tests never touch the real app's settings.
func makeIsolatedDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "notchling.tests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}
