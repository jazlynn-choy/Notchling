import SwiftUI

// MARK: - Shape

struct NotchShape: Shape {
    var ear: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(ear, bottomRadius) }
        set { ear = newValue.first; bottomRadius = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let e = ear, b = bottomRadius
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + e, y: r.minY + e), control: CGPoint(x: r.minX + e, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + e, y: r.maxY - b))
        p.addQuadCurve(to: CGPoint(x: r.minX + e + b, y: r.maxY), control: CGPoint(x: r.minX + e, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e - b, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - e, y: r.maxY - b), control: CGPoint(x: r.maxX - e, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - e, y: r.minY + e))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - e, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Root

struct NotchView: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var settings: NotchSettings
    let openSettings: () -> Void

    var body: some View {
        let size = model.currentSize
        ZStack(alignment: .top) {
            NotchShape(ear: model.ear, bottomRadius: model.expanded ? 20 : 10)
                .fill(Color.black)
                .frame(width: size.width + model.ear * 2, height: size.height)
                .shadow(color: .black.opacity(model.expanded ? 0.45 : 0), radius: 12, y: 4)

            Group {
                if model.expanded {
                    ExpandedView(model: model, openSettings: openSettings)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                } else {
                    CollapsedView(model: model)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: model.expanded)
        .animation(.easeOut(duration: 0.2), value: settings.wingWidth)
        .foregroundColor(.white)
    }
}

// MARK: - Collapsed wings

struct CollapsedView: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var reminders: RemindersStore

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) { leftContent; Spacer(minLength: 0) }
                .padding(.leading, 12)
                .frame(width: model.wing)

            Spacer(minLength: model.notchSize.width)

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if settings.showTodoCount && reminders.openCount > 0 {
                    Text("\(reminders.openCount)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(minWidth: 14, minHeight: 14)
                        .background(Circle().fill(Color.yellow))
                }
                if settings.showTime {
                    Text(model.now, format: .dateTime.hour().minute())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                }
                if settings.showBattery {
                    BatteryBadge(level: model.battery, charging: model.charging, showText: false)
                }
            }
            .padding(.trailing, 10)
            .frame(width: model.wing)
        }
        .opacity(model.wing < 30 ? 0 : 1)
    }

    @ViewBuilder var leftContent: some View {
        let playing = model.track?.playing == true
        switch settings.leftWing {
        case .musicOrDate where playing, .music where playing:
            EqualizerBars(active: true).frame(width: 14, height: 10)
            if model.wing > 70 {
                Text(model.track?.title ?? "").font(.system(size: 11, weight: .semibold)).lineLimit(1)
            }
        case .musicOrDate, .date:
            Text(model.now, format: .dateTime.weekday(.abbreviated).day())
                .font(.system(size: 11, weight: .semibold)).lineLimit(1)
        default:
            EmptyView()
        }
    }
}

// MARK: - Expanded panel

struct ExpandedView: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var settings: NotchSettings
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(model.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .foregroundColor(.white.opacity(0.7))
                Text(model.now, format: .dateTime.hour().minute()).monospacedDigit()
                Spacer(minLength: model.notchSize.width)
                BatteryBadge(level: model.battery, charging: model.charging, showText: true)
                IconButton(symbol: "gearshape.fill", help: "Settings", action: openSettings)
                IconButton(symbol: "power", help: "Quit Notchling") { NSApp.terminate(nil) }
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .frame(height: max(model.notchSize.height - 6, 20))
            .padding(.horizontal, 20)

            HStack(alignment: .top, spacing: 10) {
                if settings.showMusicCard {
                    NowPlayingCard(model: model).frame(width: min(210, model.expandedSize.width * 0.45))
                }
                TodoList()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct NowPlayingCard: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: model.track?.app == "Spotify"
                                         ? [Color(red: 0.11, green: 0.73, blue: 0.33), Color(red: 0.05, green: 0.3, blue: 0.15)]
                                         : [Color(red: 0.98, green: 0.24, blue: 0.4), Color(red: 0.55, green: 0.1, blue: 0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Group {
                        if model.track?.playing == true { EqualizerBars(active: true).frame(width: 20, height: 16) }
                        else { Image(systemName: "music.note").font(.system(size: 17, weight: .semibold)) }
                    })
                    .frame(width: 46, height: 46)
                    .opacity(model.track == nil ? 0.35 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.track?.title ?? "Nothing playing")
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(model.track?.artist ?? "Open Music or Spotify")
                        .font(.system(size: 10)).foregroundColor(.white.opacity(0.6)).lineLimit(1)
                }
            }
            HStack(spacing: 14) {
                ControlButton(symbol: "backward.fill") { model.control("previous track") }
                ControlButton(symbol: model.track?.playing == true ? "pause.fill" : "play.fill", size: 16) { model.control("playpause") }
                ControlButton(symbol: "forward.fill") { model.control("next track") }
            }
            .frame(maxWidth: .infinity)
            .disabled(model.track == nil)
            .opacity(model.track == nil ? 0.3 : 1)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }
}

struct ControlButton: View {
    let symbol: String
    var size: CGFloat = 12
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - To-do list (Apple Reminders)

struct TodoList: View {
    @EnvironmentObject var reminders: RemindersStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "checklist").font(.system(size: 10, weight: .bold)).foregroundColor(.yellow)
                Text("Reminders").font(.system(size: 11, weight: .bold))
                if reminders.openCount > 0 {
                    Text("\(reminders.openCount)").font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
                Spacer()
            }

            switch reminders.access {
            case .granted: list
            case .unknown:
                Spacer(minLength: 0)
                Button("Connect to Reminders") { reminders.requestAccess() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.yellow)).foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            case .denied:
                Text("Notchling can't see Reminders. Allow it in System Settings → Privacy & Security → Reminders.")
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                }
                .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundColor(.yellow)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 5) {
                if reminders.items.isEmpty {
                    Text("All done 🎉").font(.system(size: 11)).foregroundColor(.white.opacity(0.4))
                }
                ForEach(reminders.items) { t in
                    HStack(spacing: 7) {
                        Button { reminders.toggle(t) } label: {
                            Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 12))
                                .foregroundColor(t.done ? .green : .white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        Text(t.text)
                            .font(.system(size: 11))
                            .strikethrough(t.done)
                            .foregroundColor(.white.opacity(t.done ? 0.4 : 0.9))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let due = t.due { DueLabel(date: due) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)

        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 9, weight: .bold)).foregroundColor(.white.opacity(0.5))
            TextField("Add a reminder", text: $reminders.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .onSubmit { reminders.add(reminders.draft); reminders.draft = "" }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))
    }
}

struct DueLabel: View {
    let date: Date
    var body: some View {
        let cal = Calendar.current
        let overdue = date < cal.startOfDay(for: Date())
        let text = cal.isDateInToday(date) ? "Today"
            : cal.isDateInTomorrow(date) ? "Tomorrow"
            : date.formatted(.dateTime.month(.abbreviated).day())
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(overdue ? .red : .white.opacity(0.45))
    }
}

// MARK: - Small pieces

struct BatteryBadge: View {
    let level: Int
    let charging: Bool
    let showText: Bool

    var color: Color { charging ? .green : (level <= 20 ? .red : .white) }

    var body: some View {
        HStack(spacing: 3) {
            if showText {
                Text("\(level)%").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.5), lineWidth: 1)
                    .frame(width: 20, height: 10)
                RoundedRectangle(cornerRadius: 1.5).fill(color)
                    .frame(width: max(2, 16 * CGFloat(level) / 100), height: 6)
                    .padding(.leading, 2)
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 6, weight: .black))
                        .foregroundColor(.black).frame(width: 20)
                }
            }
        }
    }
}

struct EqualizerBars: View {
    let active: Bool
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: geo.size.width * 0.12) {
                    ForEach(0..<4) { i in
                        let v = 0.35 + 0.65 * abs(sin(t * (3.1 + Double(i) * 1.3) + Double(i)))
                        Capsule().fill(Color.white).frame(height: geo.size.height * v)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}
