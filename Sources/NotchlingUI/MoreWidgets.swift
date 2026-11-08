import NotchlingCore
import SwiftUI

// MARK: - Wing widgets

struct WeatherWing: View {
    @EnvironmentObject var weather: WeatherStore

    var body: some View {
        if let report = weather.report {
            HStack(spacing: 3) {
                Image(systemName: report.condition.symbol(isDay: report.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 10))
                Text(WeatherStore.degrees(report.temperature))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(report.condition.label), \(WeatherStore.degrees(report.temperature))")
        }
    }
}

struct WorldClockWing: View {
    let now: Date
    let wingWidth: CGFloat
    @EnvironmentObject var settings: NotchSettings

    var body: some View {
        if let id = settings.worldClockZones.first, let zone = TimeZone(identifier: id) {
            HStack(spacing: 3) {
                if wingWidth > 110 {
                    Text(WorldClock.cityName(for: id)).foregroundStyle(.white.opacity(0.6))
                } else {
                    Image(systemName: "globe").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                }
                Text(WorldClock.time(in: zone, at: now)).monospacedDigit().fixedSize()
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .accessibilityElement(children: .combine)
        }
    }
}

struct CountdownWing: View {
    let now: Date
    @EnvironmentObject var settings: NotchSettings

    var body: some View {
        let days = Countdown.days(until: settings.countdownDate, from: now)
        HStack(spacing: 3) {
            Image(systemName: "hourglass").font(.system(size: 9, weight: .bold)).foregroundStyle(.purple)
            Text(Countdown.compact(days: days))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(settings.countdownTitle): \(days) days")
    }
}

// MARK: - Panel cards

struct WeatherCard: View {
    @EnvironmentObject var weather: WeatherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let place = weather.place {
                Text(place.name).font(.system(size: 11, weight: .bold)).lineLimit(1)
                if let report = weather.report {
                    HStack(spacing: 6) {
                        Image(systemName: report.condition.symbol(isDay: report.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.system(size: 24))
                        Text(WeatherStore.degrees(report.temperature))
                            .font(.system(size: 26, weight: .light, design: .rounded))
                    }
                    Text(report.condition.label).font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                    Text("H \(WeatherStore.degrees(report.high))  L \(WeatherStore.degrees(report.low))")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                } else if let error = weather.lastError {
                    Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                } else {
                    ProgressView().controlSize(.small)
                }
            } else {
                Image(systemName: "cloud.sun").font(.system(size: 18)).foregroundStyle(.white.opacity(0.5))
                Text("Pick a city in Settings").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .cardStyle()
    }
}

struct WorldClockCard: View {
    let now: Date
    @EnvironmentObject var settings: NotchSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if settings.worldClockZones.isEmpty {
                Text("Add cities in Settings").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
            }
            ForEach(settings.worldClockZones, id: \.self) { id in
                if let zone = TimeZone(identifier: id) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(WorldClock.cityName(for: id)).font(.system(size: 11, weight: .semibold))
                            Text([WorldClock.dayLabel(in: zone, at: now), WorldClock.offsetLabel(for: zone, at: now)]
                                    .compactMap { $0 }.joined(separator: ", "))
                                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer(minLength: 4)
                        Text(WorldClock.time(in: zone, at: now))
                            .font(.system(size: 15, weight: .light, design: .rounded))
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .cardStyle()
    }
}

struct CountdownCard: View {
    let now: Date
    @EnvironmentObject var settings: NotchSettings

    var body: some View {
        let days = Countdown.days(until: settings.countdownDate, from: now)
        VStack(spacing: 2) {
            Text(settings.countdownTitle.isEmpty ? "Countdown" : settings.countdownTitle)
                .font(.system(size: 11, weight: .bold)).lineLimit(1)
            Text(days == 0 ? "🎉" : "\(abs(days))")
                .font(.system(size: 34, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.purple.opacity(0.9))
                .minimumScaleFactor(0.5)
            Text(Countdown.caption(days: days)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            Text(settings.countdownDate, format: .dateTime.day().month(.abbreviated).year())
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .cardStyle()
    }
}

struct NotesCard: View {
    @EnvironmentObject var notes: NotesStore
    @Environment(\.notchSnapshot) private var snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "note.text").font(.system(size: 10, weight: .bold)).foregroundStyle(.yellow)
                Text("Notes").font(.system(size: 11, weight: .bold))
            }
            ZStack(alignment: .topLeading) {
                if notes.text.isEmpty {
                    Text("Jot something down…").font(.system(size: 11)).foregroundStyle(.white.opacity(0.35))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                }
                if snapshot {
                    Text(notes.text).font(.system(size: 11)).padding(.leading, 5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    TextEditor(text: $notes.text)
                        .font(.system(size: 11))
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                        .accessibilityLabel("Notes")
                }
            }
        }
        .cardStyle()
    }
}
