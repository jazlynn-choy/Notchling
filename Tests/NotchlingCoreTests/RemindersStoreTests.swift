import Foundation
import Testing
@testable import NotchlingCore

@MainActor
@Suite("RemindersStore")
struct RemindersStoreTests {
    let provider = FakeRemindersProvider()

    func makeStore(listID: String? = nil) -> RemindersStore {
        RemindersStore(provider: provider, listID: listID, completionDelay: .milliseconds(20))
    }

    @Test func loadsAndSortsReminders() async {
        let soon = Date(timeIntervalSinceNow: 3600)
        provider.reminders[""] = [Todo(id: "b", title: "Undated"), Todo(id: "a", title: "Soon", due: soon)]
        let store = makeStore()
        await store.reload()
        #expect(store.items.map(\.id) == ["a", "b"])
        #expect(store.openCount == 2)
        #expect(store.lists.count == 2)
    }

    @Test func showsTheSelectedList() async {
        provider.reminders[""] = [Todo(id: "default", title: "Default")]
        provider.reminders["work"] = [Todo(id: "w1", title: "Ship it")]
        let store = makeStore(listID: "work")
        await store.reload()
        #expect(store.items.map(\.id) == ["w1"])
    }

    @Test func doesNothingWithoutAccess() async {
        provider.access = .notDetermined
        provider.reminders[""] = [Todo(id: "x", title: "Hidden")]
        let store = makeStore()
        await store.reload()
        #expect(store.items.isEmpty)
    }

    @Test func requestingAccessLoadsItems() async {
        provider.access = .notDetermined
        provider.reminders[""] = [Todo(id: "x", title: "Now visible")]
        let store = makeStore()
        await store.requestAccess()
        #expect(store.access == .granted)
        #expect(store.items.count == 1)
    }

    @Test func deniedAccessIsReported() async {
        provider.access = .notDetermined
        provider.grantOnRequest = false
        let store = makeStore()
        await store.requestAccess()
        #expect(store.access == .denied)
    }

    @Test func addingTrimsAndClearsTheDraft() async {
        let store = makeStore()
        store.draft = "  Buy milk  "
        await store.addDraft()
        #expect(store.draft.isEmpty)
        #expect(store.items.map(\.title) == ["Buy milk"])
    }

    @Test func blankDraftIsIgnored() async {
        let store = makeStore()
        store.draft = "   "
        await store.addDraft()
        #expect(store.items.isEmpty)
        #expect(store.draft == "   ")
    }

    @Test func tickingCompletesAfterTheDelay() async {
        provider.reminders[""] = [Todo(id: "a", title: "Task")]
        let store = makeStore()
        await store.reload()

        store.toggle(store.items[0])
        #expect(store.items[0].isDone)          // checked immediately…
        #expect(provider.completedIDs.isEmpty)  // …but not yet saved

        await store.settlePendingCompletions()
        #expect(provider.completedIDs == ["a"])
        #expect(store.items.isEmpty)
    }

    @Test func tickingTwiceCancelsTheCompletion() async throws {
        provider.reminders[""] = [Todo(id: "a", title: "Task")]
        let store = makeStore()
        await store.reload()

        store.toggle(store.items[0])
        store.toggle(store.items[0])
        try await Task.sleep(for: .milliseconds(60))
        #expect(provider.completedIDs.isEmpty)
        #expect(store.items.first?.isDone == false)
    }

    @Test func tickedRowSurvivesAReloadUntilItCommits() async {
        provider.reminders[""] = [Todo(id: "a", title: "Task"), Todo(id: "b", title: "Other")]
        let store = makeStore()
        await store.reload()
        store.toggle(store.items[0])

        provider.reminders[""] = [Todo(id: "b", title: "Other")]   // vanished upstream mid-tick
        await store.reload()
        #expect(store.items.map(\.id) == ["a", "b"])
        #expect(store.items[0].isDone)
        await store.settlePendingCompletions()
    }

    @Test func failedCompletionUnticksAndReportsError() async {
        provider.reminders[""] = [Todo(id: "a", title: "Task")]
        provider.failNextComplete = true
        let store = makeStore()
        await store.reload()

        store.toggle(store.items[0])
        await store.settlePendingCompletions()
        #expect(store.items.first?.isDone == false)
        #expect(store.lastError == RemindersError.notFound.errorDescription)
    }

    @Test func fetchErrorIsSurfacedThenClearedOnSuccess() async {
        provider.failFetch = true
        let store = makeStore()
        await store.reload()
        #expect(store.lastError != nil)

        provider.failFetch = false
        await store.reload()
        #expect(store.lastError == nil)
    }

    @Test func externalChangesTriggerAReload() async throws {
        let store = makeStore()
        await store.reload()
        provider.reminders[""] = [Todo(id: "phone", title: "Added on iPhone")]
        provider.simulateExternalChange()
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.items.map(\.id) == ["phone"])
    }
}
