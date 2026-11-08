import Foundation

/// The chosen city, unit and latest report, plus the city search used in Settings.
@MainActor
public final class WeatherStore: ObservableObject {
    enum Key {
        static let place = "weatherPlace"
        static let unit = "weatherUnit"
    }

    @Published public private(set) var place: Place?
    @Published public var unit: TemperatureUnit {
        didSet {
            defaults.set(unit.rawValue, forKey: Key.unit)
            if unit != oldValue { report = nil; Task { await refresh(force: true) } }
        }
    }
    @Published public private(set) var report: WeatherReport?
    @Published public private(set) var lastError: String?

    /// City search in Settings.
    @Published public var placeQuery = "" {
        didSet { if placeQuery != oldValue { schedulePlaceSearch() } }
    }
    @Published public private(set) var placeResults: [Place] = []

    /// Weather changes slowly; refetching more often only spends the free API's goodwill.
    public static let maxAge: TimeInterval = 20 * 60

    private let provider: WeatherProviding
    private let defaults: UserDefaults
    private let clock: () -> Date
    private let debounce: Duration
    private var searchTask: Task<Void, Never>?

    public init(provider: WeatherProviding, defaults: UserDefaults = .standard,
                locale: Locale = .current, clock: @escaping () -> Date = Date.init,
                debounce: Duration = .milliseconds(350)) {
        self.provider = provider
        self.defaults = defaults
        self.clock = clock
        self.debounce = debounce
        unit = TemperatureUnit(rawValue: defaults.string(forKey: Key.unit) ?? "") ?? .default(for: locale)
        if let raw = defaults.dictionary(forKey: Key.place),
           let name = raw["name"] as? String, let lat = raw["lat"] as? Double, let lon = raw["lon"] as? Double {
            place = Place(name: name, region: raw["region"] as? String ?? "", latitude: lat, longitude: lon)
        }
    }

    public func choose(_ place: Place) {
        self.place = place
        defaults.set(["name": place.name, "region": place.region, "lat": place.latitude, "lon": place.longitude],
                     forKey: Key.place)
        placeQuery = ""
        report = nil
        Task { await refresh(force: true) }
    }

    /// Fetches unless the last report is still fresh.
    public func refresh(force: Bool = false) async {
        guard let place else { return }
        if !force, let report, clock().timeIntervalSince(report.fetchedAt) < Self.maxAge { return }
        do {
            report = try await provider.report(for: place, unit: unit)
            lastError = nil
        } catch {
            // Keep showing the last report; a blip in the network shouldn't blank the widget.
            lastError = "Couldn't update the weather."
        }
    }

    /// "18°", rounded, without the unit (the wing has no room for it).
    nonisolated public static func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    private func schedulePlaceSearch() {
        searchTask?.cancel()
        let query = placeQuery
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { placeResults = []; return }
        let provider = provider, debounce = debounce
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            let found = (try? await provider.searchPlaces(query)) ?? []
            guard !Task.isCancelled else { return }
            self?.placeResults = found
        }
    }

    /// Test hook.
    func settleSearch() async { await searchTask?.value }
}
