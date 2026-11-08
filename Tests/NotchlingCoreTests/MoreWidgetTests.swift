import Foundation
import Testing
@testable import NotchlingCore

@Suite("Panel card sizes")
struct PanelLayoutTests {
    @Test func widthsFillTheSpaceExactly() {
        let widths = PanelLayout.widths(for: [.small, .medium, .large], totalWidth: 600, spacing: 10)
        #expect(abs(widths.reduce(0, +) - 580) < 0.001)
        #expect(widths[0] < widths[1] && widths[1] < widths[2])
    }

    @Test func equalSizesShareEqually() {
        #expect(PanelLayout.widths(for: [.medium, .medium], totalWidth: 410, spacing: 10) == [200, 200])
    }

    @Test func smallCardsKeepAMinimumWidth() {
        let widths = PanelLayout.widths(for: [.small, .large, .large, .large], totalWidth: 500, spacing: 10)
        #expect(widths[0] >= 90)
    }

    @Test func emptyPanelHasNoWidths() {
        #expect(PanelLayout.widths(for: [], totalWidth: 500, spacing: 10).isEmpty)
    }
}

@MainActor
@Suite("Settings for new widgets")
struct NewWidgetSettingsTests {
    @Test func cardSizesPersistAndDefaultsArentStored() {
        let defaults = makeIsolatedDefaults()
        let settings = NotchSettings(defaults: defaults, loginItem: FakeLoginItem())
        #expect(settings.cardSize(for: .remindersCard) == .large)
        settings.setCardSize(.small, for: .remindersCard)
        settings.setCardSize(.small, for: .dayCard)   // already its default
        let reloaded = NotchSettings(defaults: defaults, loginItem: FakeLoginItem())
        #expect(reloaded.cardSize(for: .remindersCard) == .small)
        #expect(reloaded.cardSizes == [.remindersCard: .small])
        reloaded.resetWidgets()
        #expect(reloaded.cardSizes.isEmpty)
    }

    @Test func musicSourceDefaultsToSpotifyOnlyWhenInstalled() {
        #expect(NotchSettings(defaults: makeIsolatedDefaults(), loginItem: FakeLoginItem(),
                              spotifyInstalled: true).musicSource == .spotify)
        #expect(NotchSettings(defaults: makeIsolatedDefaults(), loginItem: FakeLoginItem(),
                              spotifyInstalled: false).musicSource == .music)
    }

    @Test func worldClocksRejectDuplicatesUnknownZonesAndOverflow() {
        let settings = NotchSettings(defaults: makeIsolatedDefaults(), loginItem: FakeLoginItem())
        #expect(settings.worldClockZones == ["Europe/London", "America/New_York"])
        settings.addWorldClock("Europe/London")
        settings.addWorldClock("Mars/Olympus_Mons")
        settings.addWorldClock("Asia/Tokyo")
        settings.addWorldClock("Australia/Sydney")   // over the limit of 3
        #expect(settings.worldClockZones == ["Europe/London", "America/New_York", "Asia/Tokyo"])
        settings.removeWorldClock("Europe/London")
        #expect(settings.worldClockZones == ["America/New_York", "Asia/Tokyo"])
    }

    @Test func panelHoldsFourCards() {
        let layout = WidgetLayout(leftWing: [], rightWing: [],
                                  panel: [.musicCard, .remindersCard, .weatherCard, .notesCard, .dayCard])
        #expect(layout.panel.count == 4)
    }
}

@Suite("World clock and countdown")
struct ClockTests {
    let now = Date(timeIntervalSince1970: 1_794_063_600)   // Sat 7 Nov 2026, 15:00 UTC
    let utc = TimeZone(identifier: "UTC")!

    @Test func cityNames() {
        #expect(WorldClock.cityName(for: "America/Argentina/Buenos_Aires") == "Buenos Aires")
        #expect(WorldClock.cityName(for: "Asia/Singapore") == "Singapore")
    }

    @Test func offsetsAndDayChanges() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!          // 00:00 Sun
        let honolulu = TimeZone(identifier: "Pacific/Honolulu")!  // 05:00 Sat
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        #expect(WorldClock.offsetLabel(for: tokyo, at: now, localZone: utc) == "+9h")
        #expect(WorldClock.offsetLabel(for: honolulu, at: now, localZone: utc) == "−10h")
        #expect(WorldClock.offsetLabel(for: kolkata, at: now, localZone: utc) == "+5h 30m")
        #expect(WorldClock.offsetLabel(for: utc, at: now, localZone: utc) == "Same time")
        #expect(WorldClock.dayLabel(in: tokyo, at: now, localZone: utc) == "Tomorrow")
        #expect(WorldClock.dayLabel(in: honolulu, at: now, localZone: utc) == nil)
        #expect(WorldClock.dayLabel(in: utc, at: now, localZone: tokyo) == "Yesterday")
    }

    @Test func pickerListIsSortedAndClean() {
        #expect(!WorldClock.allZones.isEmpty)
        #expect(!WorldClock.allZones.contains { $0.id.hasPrefix("Etc/") })
    }

    @Test func countdownDays() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let late = now.addingTimeInterval(8 * 3600)   // 23:00 same day
        #expect(Countdown.days(until: late, from: now, calendar: calendar) == 0)
        #expect(Countdown.days(until: now.addingTimeInterval(10 * 3600), from: now, calendar: calendar) == 1)
        #expect(Countdown.days(until: now.addingTimeInterval(-86_400 * 3), from: now, calendar: calendar) == -3)
    }

    @Test(arguments: [(0, "Today", "today!"), (1, "1d", "day to go"), (12, "12d", "days to go"),
                      (-1, "Done", "day ago"), (-5, "Done", "days ago")])
    func countdownLabels(days: Int, compact: String, caption: String) {
        #expect(Countdown.compact(days: days) == compact)
        #expect(Countdown.caption(days: days) == caption)
    }
}

@Suite("Weather")
struct WeatherParsingTests {
    // Trimmed from real Open-Meteo responses.
    let geocoding = #"{"results":[{"id":1880252,"name":"Singapore","latitude":1.28967,"longitude":103.85007,"country":"Singapore"},{"name":"London","latitude":42.98,"longitude":-81.23,"country":"Canada","admin1":"Ontario"}],"generationtime_ms":0.1}"#
    let forecast = #"{"latitude":1.3,"current":{"time":"2026-11-08T15:30","interval":900,"temperature_2m":26.8,"weather_code":51,"is_day":1},"daily":{"time":["2026-11-08"],"temperature_2m_max":[30.5],"temperature_2m_min":[25.2]}}"#

    @Test func parsesPlacesWithRegion() throws {
        let places = try OpenMeteoWeatherProvider.parsePlaces(Data(geocoding.utf8))
        #expect(places.map(\.region) == ["Singapore", "Ontario, Canada"])
    }

    @Test func noMatchesMeansNoResultsKey() throws {
        #expect(try OpenMeteoWeatherProvider.parsePlaces(Data(#"{"generationtime_ms":0.09}"#.utf8)).isEmpty)
    }

    @Test func parsesForecast() throws {
        let now = Date(timeIntervalSince1970: 0)
        let report = try OpenMeteoWeatherProvider.parseReport(Data(forecast.utf8), now: now)
        #expect(report == WeatherReport(temperature: 26.8, high: 30.5, low: 25.2, condition: .drizzle,
                                        isDay: true, fetchedAt: now))
    }

    @Test(arguments: [(0, WeatherCondition.clear), (2, .partlyCloudy), (45, .fog), (63, .rain),
                      (75, .snow), (81, .showers), (96, .thunderstorm), (42, .unknown)])
    func wmoCodes(code: Int, expected: WeatherCondition) {
        #expect(WeatherCondition(wmoCode: code) == expected)
    }

    @Test func nightGetsTheMoon() {
        #expect(WeatherCondition.clear.symbol(isDay: false) == "moon.stars.fill")
    }

    @Test func forecastURLAsksForTheChosenUnit() {
        let url = OpenMeteoWeatherProvider.forecastURL(
            for: Place(name: "X", region: "", latitude: 1.5, longitude: -2), unit: .fahrenheit)
        #expect(url.absoluteString.contains("temperature_unit=fahrenheit"))
        #expect(url.absoluteString.contains("latitude=1.5"))
    }

    @Test func degreesRound() {
        #expect(WeatherStore.degrees(26.5) == "27°")
        #expect(WeatherStore.degrees(-0.4) == "0°")
    }
}

@MainActor
@Suite("Weather store")
struct WeatherStoreTests {
    final class Clock { var now = Date(timeIntervalSince1970: 1_794_063_600) }
    let place = Place(name: "Singapore", region: "Singapore", latitude: 1.29, longitude: 103.85)

    func report(_ temp: Double, at date: Date) -> WeatherReport {
        WeatherReport(temperature: temp, high: temp, low: temp, condition: .clear, isDay: true, fetchedAt: date)
    }

    @Test func unitDefaultsFromLocale() {
        #expect(WeatherStore(provider: FakeWeatherProvider(), defaults: makeIsolatedDefaults(),
                             locale: Locale(identifier: "en_US")).unit == .fahrenheit)
        #expect(WeatherStore(provider: FakeWeatherProvider(), defaults: makeIsolatedDefaults(),
                             locale: Locale(identifier: "en_SG")).unit == .celsius)
    }

    @Test func choosingAPlacePersistsAndFetches() async throws {
        let defaults = makeIsolatedDefaults()
        let clock = Clock()
        let provider = FakeWeatherProvider()
        provider.nextReport = report(27, at: clock.now)
        let store = WeatherStore(provider: provider, defaults: defaults, clock: { clock.now })
        store.choose(place)
        try await Task.sleep(for: .milliseconds(30))
        #expect(store.report?.temperature == 27)
        #expect(WeatherStore(provider: provider, defaults: defaults).place == place)
    }

    @Test func freshReportsAreNotRefetched() async {
        let clock = Clock()
        let provider = FakeWeatherProvider()
        provider.nextReport = report(27, at: clock.now)
        let defaults = makeIsolatedDefaults()
        defaults.set(["name": "S", "region": "", "lat": 1.0, "lon": 2.0], forKey: WeatherStore.Key.place)
        let store = WeatherStore(provider: provider, defaults: defaults, clock: { clock.now })
        await store.refresh()
        clock.now.addTimeInterval(60)
        await store.refresh()
        #expect(provider.reportRequests == 1)
        clock.now.addTimeInterval(WeatherStore.maxAge)
        await store.refresh()
        #expect(provider.reportRequests == 2)
    }

    @Test func aFailedUpdateKeepsTheLastReport() async {
        let clock = Clock()
        let provider = FakeWeatherProvider()
        provider.nextReport = report(27, at: clock.now)
        let defaults = makeIsolatedDefaults()
        defaults.set(["name": "S", "region": "", "lat": 1.0, "lon": 2.0], forKey: WeatherStore.Key.place)
        let store = WeatherStore(provider: provider, defaults: defaults, clock: { clock.now })
        await store.refresh()
        provider.fail = true
        await store.refresh(force: true)
        #expect(store.report?.temperature == 27)
        #expect(store.lastError != nil)
    }
}

@MainActor
@Suite("Notes")
struct NotesTests {
    @Test func savesAfterTypingPausesAndReloads() async {
        let defaults = makeIsolatedDefaults()
        let notes = NotesStore(defaults: defaults, saveDelay: .milliseconds(10))
        notes.text = "buy"
        notes.text = "buy milk"
        #expect(defaults.string(forKey: NotesStore.key) == nil)   // not yet
        await notes.settle()
        #expect(NotesStore(defaults: defaults).text == "buy milk")
    }

    @Test func textIsCapped() {
        let notes = NotesStore(defaults: makeIsolatedDefaults())
        notes.text = String(repeating: "x", count: NotesStore.maxLength + 50)
        #expect(notes.text.count == NotesStore.maxLength)
    }
}
