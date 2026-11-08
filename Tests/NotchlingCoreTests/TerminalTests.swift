import Foundation
import NotchlingActivity
import Testing
@testable import NotchlingCore

@Suite("notch command: output parsing")
struct OutputParserTests {
    @Test(arguments: [
        ("Downloading 45%", 0.45), ("[=====>   ] 62.5 %", 0.625), ("Compiling 3/10", 0.3),
        ("Step 2 of 4", 0.5), ("\u{1B}[32m 80%\u{1B}[0m", 0.8),
        ("10% then 20%", 0.2),          // the latest figure wins
    ])
    func findsProgress(line: String, expected: Double) {
        #expect(abs((OutputParser.progress(in: line) ?? -1) - expected) < 1e-9)
    }

    @Test(arguments: ["no numbers here", "error 404", "150%", "11/10 apples", "v2/0"])
    func ignoresNonProgress(line: String) {
        #expect(OutputParser.progress(in: line) == nil)
    }

    @Test func stripsColoursAndRedraws() {
        #expect(OutputParser.stripANSI("\u{1B}[1;31merror\u{1B}[0m: bad") == "error: bad")
        #expect(OutputParser.stripANSI("10%\r20%\r30% done  ") == "30% done")
    }

    @Test func durations() {
        #expect(OutputParser.duration(0.25) == "250ms")
        #expect(OutputParser.duration(12.4) == "12s")
        #expect(OutputParser.duration(65) == "1m 5s")
    }
}

@MainActor
@Suite("notch command: activity store")
struct ActivityStoreTests {
    let now = Date(timeIntervalSince1970: 1_794_063_600)

    func makeStore() -> (ActivityStore, ActivityFolder) {
        let folder = ActivityFolder(url: makeTempDirectory())
        return (ActivityStore(folder: folder), folder)
    }

    @Test func chimesWhenACommandFinishesButNotForOldOnes() throws {
        let (store, folder) = makeStore()
        try folder.write(Activity(id: "old", title: "Old", state: .succeeded, updatedAt: now))
        var finished: [String] = []
        store.onFinished = { finished.append("\($0.title) \($0.state.rawValue)") }
        store.refresh(now: now)
        #expect(finished.isEmpty)

        try folder.write(Activity(id: "b", title: "Build", state: .running, updatedAt: now))
        store.refresh(now: now)
        try folder.write(Activity(id: "b", title: "Build", state: .failed, updatedAt: now))
        store.refresh(now: now)
        store.refresh(now: now)
        try folder.write(Activity(id: "m", title: "Deployed", state: .info, updatedAt: now))
        store.refresh(now: now)
        #expect(finished == ["Build failed", "Deployed info"])
    }

    @Test func killedCommandsAreShownAsStopped() throws {
        let (store, folder) = makeStore()
        try folder.write(Activity(id: "b", title: "Build", state: .running,
                                  updatedAt: now.addingTimeInterval(-ActivityStore.lostAfter - 1)))
        store.refresh(now: now)
        #expect(store.activities.first?.state == .failed)
        #expect(store.activities.first?.detail == "Stopped responding")
    }

    @Test func oldFinishedActivitiesAreCleanedUp() throws {
        let (store, folder) = makeStore()
        try folder.write(Activity(id: "x", title: "X", state: .succeeded,
                                  updatedAt: now.addingTimeInterval(-ActivityStore.keepFinished - 1)))
        store.refresh(now: now)
        #expect(store.activities.isEmpty)
        #expect(folder.readAll().isEmpty)
    }

    @Test func wingShowsRunningFirstThenRecentResults() throws {
        let (store, folder) = makeStore()
        try folder.write(Activity(id: "a", title: "Tests", state: .succeeded, updatedAt: now))
        try folder.write(Activity(id: "b", title: "Build", state: .running, updatedAt: now.addingTimeInterval(-5)))
        store.refresh(now: now)
        #expect(store.headline(at: now)?.title == "Build")
        try folder.write(Activity(id: "b", title: "Build", state: .succeeded, updatedAt: now))
        store.refresh(now: now)
        #expect(store.headline(at: now)?.isFinished == true)
        #expect(store.headline(at: now.addingTimeInterval(ActivityStore.headlineFor + 1)) == nil)
    }

    @Test func activityIDsCannotEscapeTheFolder() throws {
        let dir = makeTempDirectory()
        let folder = ActivityFolder(url: dir.appendingPathComponent("activities"))
        try folder.write(Activity(id: "../../escape", title: "X", state: .info))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("escape.json").path))
        #expect(folder.readAll().count == 1)
    }
}

@Suite("notch command: installer")
struct CommandInstallerTests {
    @Test func prefersAWritableFolderAlreadyOnPath() {
        let brew = CommandInstaller.Location(directory: URL(fileURLWithPath: "/opt/homebrew/bin"), isWritable: true, isOnPath: true)
        let usr = CommandInstaller.Location(directory: URL(fileURLWithPath: "/usr/local/bin"), isWritable: false, isOnPath: true)
        let local = CommandInstaller.Location(directory: URL(fileURLWithPath: "/h/.local/bin"), isWritable: true, isOnPath: false)
        #expect(CommandInstaller.choose(from: [usr, brew, local]) == brew)
        #expect(CommandInstaller.choose(from: [usr, local]) == local)
        #expect(CommandInstaller.choose(from: [usr]) == nil)
    }

    @Test func installsALinkAndNeverReplacesSomeoneElsesCommand() throws {
        let root = makeTempDirectory()
        let source = root.appendingPathComponent("Notchling.app/Contents/MacOS/notch")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: source.path, contents: Data("#!/bin/sh\n".utf8))
        let installer = CommandInstaller(source: source)
        let bin = CommandInstaller.Location(directory: root.appendingPathComponent("bin"), isWritable: true, isOnPath: true)

        let link = try installer.install(into: bin)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == source.path)
        #expect(installer.installedLocation(in: [bin]) == link)
        _ = try installer.install(into: bin)   // reinstalling over our own link is fine

        let other = CommandInstaller.Location(directory: root.appendingPathComponent("other"), isWritable: true, isOnPath: true)
        try FileManager.default.createDirectory(at: other.directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: other.directory.appendingPathComponent("notch").path, contents: Data())
        #expect(throws: CommandInstaller.InstallError.self) { try installer.install(into: other) }

        installer.uninstall(from: [bin, other])
        #expect(installer.installedLocation(in: [bin]) == nil)
        #expect(FileManager.default.fileExists(atPath: other.directory.appendingPathComponent("notch").path))
    }
}
