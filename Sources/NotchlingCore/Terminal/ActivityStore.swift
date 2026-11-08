import Foundation
import NotchlingActivity

/// Terminal activities from the `notch` command, for the activity widgets.
@MainActor
public final class ActivityStore: ObservableObject {
    @Published public private(set) var activities: [Activity] = []
    /// Called when a command finishes or a message arrives, so the app can chime.
    /// Not called for what was already there at launch.
    public var onFinished: ((Activity) -> Void)?

    /// Finished activities stay listed this long, then their files are removed.
    public static let keepFinished: TimeInterval = 10 * 60
    /// `notch run` writes at least every 10 s; silence for this long means it was killed.
    public static let lostAfter: TimeInterval = 45
    /// How long a finished activity holds the wing.
    public static let headlineFor: TimeInterval = 8

    private let folder: ActivityFolder
    private var seen: [String: Activity.State] = [:]
    private var hasLoaded = false

    public init(folder: ActivityFolder = ActivityFolder()) {
        self.folder = folder
    }

    public func refresh(now: Date = Date()) {
        var next: [Activity] = []
        for var activity in folder.readAll() {
            let age = now.timeIntervalSince(activity.updatedAt)
            if activity.isFinished && age > Self.keepFinished {
                folder.remove(id: activity.id)
                continue
            }
            if activity.state == .running && age > Self.lostAfter {
                activity.state = .failed
                activity.detail = "Stopped responding"
            }
            next.append(activity)
        }
        next.sort { ($0.isFinished ? 1 : 0, $1.updatedAt) < ($1.isFinished ? 1 : 0, $0.updatedAt) }

        if hasLoaded {
            for activity in next where activity.isFinished && seen[activity.id] != activity.state {
                onFinished?(activity)
            }
        }
        seen = Dictionary(uniqueKeysWithValues: next.map { ($0.id, $0.state) })
        hasLoaded = true
        if next != activities { activities = next }
    }

    /// What the wing shows: the newest running command, else something that just finished.
    public func headline(at now: Date) -> Activity? {
        activities.first { $0.state == .running }
            ?? activities.filter { now.timeIntervalSince($0.updatedAt) < Self.headlineFor }
                .max { $0.updatedAt < $1.updatedAt }
    }

    public func clearFinished() {
        for activity in activities where activity.isFinished { folder.remove(id: activity.id) }
        activities.removeAll(where: \.isFinished)
    }
}
