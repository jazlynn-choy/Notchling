import Foundation

/// A city picked for the weather widget.
public struct Place: Equatable, Sendable, Identifiable {
    public var name: String
    /// "Ontario, Canada", for telling apart cities with the same name.
    public var region: String
    public var latitude: Double
    public var longitude: Double

    public var id: String { "\(latitude),\(longitude)" }

    public init(name: String, region: String, latitude: Double, longitude: Double) {
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum TemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case celsius, fahrenheit
    public var id: String { rawValue }
    public var symbol: String { self == .celsius ? "°C" : "°F" }

    /// Fahrenheit for the US and a few others, Celsius everywhere else.
    public static func `default`(for locale: Locale) -> TemperatureUnit {
        locale.measurementSystem == .us ? .fahrenheit : .celsius
    }
}

public struct WeatherReport: Equatable, Sendable {
    public var temperature: Double
    public var high: Double
    public var low: Double
    public var condition: WeatherCondition
    public var isDay: Bool
    public var fetchedAt: Date

    public init(temperature: Double, high: Double, low: Double, condition: WeatherCondition, isDay: Bool,
                fetchedAt: Date) {
        self.temperature = temperature
        self.high = high
        self.low = low
        self.condition = condition
        self.isDay = isDay
        self.fetchedAt = fetchedAt
    }
}

/// WMO weather interpretation codes, grouped into what the widget can draw.
public enum WeatherCondition: Equatable, Sendable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, showers, thunderstorm, unknown

    public init(wmoCode: Int) {
        switch wmoCode {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67: self = .rain
        case 71...77, 85, 86: self = .snow
        case 80...82: self = .showers
        case 95...99: self = .thunderstorm
        default: self = .unknown
        }
    }

    public var label: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .showers: return "Showers"
        case .thunderstorm: return "Thunderstorm"
        case .unknown: return "—"
        }
    }

    /// SF Symbol, with night variants where they exist.
    public func symbol(isDay: Bool) -> String {
        switch self {
        case .clear: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case .partlyCloudy: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .showers: return "cloud.heavyrain.fill"
        case .thunderstorm: return "cloud.bolt.rain.fill"
        case .unknown: return "questionmark"
        }
    }
}

public protocol WeatherProviding: Sendable {
    func searchPlaces(_ query: String) async throws -> [Place]
    func report(for place: Place, unit: TemperatureUnit) async throws -> WeatherReport
}

/// Open-Meteo: free, no API key, no account. Only the chosen city's coordinates are sent.
public struct OpenMeteoWeatherProvider: WeatherProviding {
    let http: HTTPClient
    let clock: @Sendable () -> Date

    public init(http: HTTPClient = URLSessionHTTPClient(), clock: @escaping @Sendable () -> Date = { Date() }) {
        self.http = http
        self.clock = clock
    }

    public func searchPlaces(_ query: String) async throws -> [Place] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "6"),
                                 .init(name: "language", value: "en"), .init(name: "format", value: "json")]
        return try Self.parsePlaces(try await get(components.url!))
    }

    public func report(for place: Place, unit: TemperatureUnit) async throws -> WeatherReport {
        try Self.parseReport(try await get(Self.forecastURL(for: place, unit: unit)), now: clock())
    }

    static func forecastURL(for place: Place, unit: TemperatureUnit) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "temperature_unit", value: unit.rawValue),
        ]
        return components.url!
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await http.send(request)
        guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    public static func parsePlaces(_ data: Data) throws -> [Place] {
        struct Response: Decodable {
            struct Result: Decodable {
                let name: String
                let latitude: Double
                let longitude: Double
                let country: String?
                let admin1: String?
            }
            let results: [Result]?   // missing entirely when nothing matches
        }
        return try JSONDecoder().decode(Response.self, from: data).results?.map {
            Place(name: $0.name, region: [$0.admin1, $0.country].compactMap { $0 }.joined(separator: ", "),
                  latitude: $0.latitude, longitude: $0.longitude)
        } ?? []
    }

    public static func parseReport(_ data: Data, now: Date) throws -> WeatherReport {
        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
                let is_day: Int
            }
            struct Daily: Decodable {
                let temperature_2m_max: [Double]
                let temperature_2m_min: [Double]
            }
            let current: Current
            let daily: Daily
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return WeatherReport(temperature: response.current.temperature_2m,
                             high: response.daily.temperature_2m_max.first ?? response.current.temperature_2m,
                             low: response.daily.temperature_2m_min.first ?? response.current.temperature_2m,
                             condition: WeatherCondition(wmoCode: response.current.weather_code),
                             isDay: response.current.is_day == 1,
                             fetchedAt: now)
    }
}
