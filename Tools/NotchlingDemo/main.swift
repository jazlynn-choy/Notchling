import AppKit
import ImageIO
import NotchlingActivity
import NotchlingCore
import NotchlingUI
import SwiftUI
import UniformTypeIdentifiers

// Renders docs/demo.gif (and docs/screenshot.png) from the app's real SwiftUI views,
// driven by demo data. No screen recording or permissions needed, and it's reproducible:
// run `make demo` after changing the UI.

/// A desktop around the notch: wallpaper, a menu bar, the notch UI, and a caption.
struct DemoScene: View {
    let model: NotchModel
    let caption: String
    let size: CGSize
    let windowHeight: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            // Close colours: GIFs have 256 colours, and a wide gradient shows bands.
            LinearGradient(colors: [Color(red: 0.13, green: 0.12, blue: 0.24), Color(red: 0.22, green: 0.16, blue: 0.32)],
                           startPoint: .top, endPoint: .bottom)
            menuBar
            NotchView(model: model, openSettings: {})
                .frame(width: size.width, height: windowHeight)
            VStack {
                Spacer()
                Text(caption)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Capsule().fill(.black.opacity(0.55)))
                    .padding(.bottom, 16)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    private var menuBar: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo").font(.system(size: 14, weight: .semibold))
            Text("Code").fontWeight(.bold)
            ForEach(["File", "Edit", "View", "Window", "Help"], id: \.self) { Text($0) }
            Spacer()
            Image(systemName: "wifi")
            Text(model.now, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(Color.black.opacity(0.18))
    }
}

struct Frame {
    let image: CGImage
    let delay: Double
}

@MainActor
final class Demo {
    let now = Date()
    let media = DemoMedia()
    let agentSource = DemoAgents()
    let approvalChannel = DemoApprovals()
    let activityFolder = ActivityFolder(url: FileManager.default.temporaryDirectory
        .appendingPathComponent("notchling-demo-\(UUID().uuidString)"))

    lazy var defaults = UserDefaults(suiteName: "notchling.demo.\(UUID().uuidString)")!
    lazy var settings = NotchSettings(defaults: defaults, loginItem: DemoLoginItem())
    lazy var model = NotchModel(notchSize: CGSize(width: 185, height: 32), media: media, power: DemoPower())
    lazy var reminders = RemindersStore(provider: DemoReminders(now: now))
    lazy var weather = WeatherStore(provider: DemoWeather(), defaults: defaults)
    lazy var agents = AgentStatusStore(source: agentSource)
    lazy var approvals = ApprovalStore(channel: approvalChannel, waitSeconds: 30)
    lazy var activities = ActivityStore(folder: activityFolder)

    let size = CGSize(width: 1000, height: 360)
    let scale: CGFloat = 1.25
    var frames: [Frame] = []
    var caption = ""

    func setUp() async {
        settings.wingWidth = 150
        settings.panelWidth = 660
        settings.panelHeight = 262
        settings.widgets = WidgetLayout(leftWing: [.agent], rightWing: [.activity, .battery],
                                        columns: [[.musicCard, .weatherCard], [.remindersCard], [.agentCard, .activityCard]])
        settings.setCardWeight(1.5, for: .musicCard)
        settings.setCardWeight(1.5, for: .remindersCard)
        settings.setCardWeight(1.8, for: .agentCard)
        settings.setCardHeights((.musicCard, 1.25), (.weatherCard, 0.75))
        model.refreshPower()
        await model.refreshMedia()
        await reminders.reload()
        weather.choose(Place(name: "Singapore", region: "Singapore", latitude: 1.29, longitude: 103.85))
        await weather.refresh(force: true)
        agent("a", "PreToolUse", tool: "Edit", detail: "/Users/me/Notchling/Sources/NotchView.swift", project: "Notchling")
        agent("b", "Stop", project: "portfolio-site", ago: 240)
    }

    // MARK: State

    func agent(_ id: String, _ event: String, tool: String? = nil, detail: String? = nil, project: String,
               message: String? = nil, ago: TimeInterval = 2) {
        agentSource.events.removeAll { $0.event.sessionID == id }
        agentSource.events.append((AgentEvent(sessionID: id, name: event, cwd: "/Users/me/\(project)", toolName: tool,
                                              toolDetail: detail, message: message), now.addingTimeInterval(-ago)))
        agents.refresh(now: now)
    }

    func build(_ progress: Double, line: String, state: Activity.State = .running) {
        try? activityFolder.write(Activity(id: "build", title: "swift build", detail: line,
                                           progress: progress, state: state, updatedAt: Date()))
        activities.refresh()
    }

    func askPermission(elapsed: TimeInterval) {
        // swiftlint:disable:next line_length - JSON exactly as Claude Code sends it
        let json = #"{"session_id":"a","hook_event_name":"PermissionRequest","cwd":"/Users/me/Notchling","tool_name":"Bash","tool_input":{"command":"npm test -- --coverage","description":"Run the test suite"}}"#
        approvalChannel.files = [("req", Data(json.utf8), model.now.addingTimeInterval(-elapsed))]
        approvals.refresh()
    }

    func clearPermission() {
        approvalChannel.files = []
        approvals.refresh()
    }

    // MARK: Rendering

    func render() -> CGImage {
        let geometry = settings.geometry(notchSize: model.notchSize)
        let scene = DemoScene(model: model, caption: caption, size: size,
                              windowHeight: geometry.windowFrame(on: CGRect(origin: .zero, size: size)).height)
            .environmentObject(settings).environmentObject(reminders).environmentObject(FocusTimer(defaults: defaults))
            .environmentObject(CalendarStore(provider: DemoCalendar()))
            .environmentObject(MusicSearch(media: media)).environmentObject(weather)
            .environmentObject(NotesStore(defaults: defaults)).environmentObject(agents)
            .environmentObject(PanelEditor()).environmentObject(approvals).environmentObject(activities)
            .environment(\.notchSnapshot, true)
        let renderer = ImageRenderer(content: scene)
        renderer.scale = scale
        guard let image = renderer.cgImage else { fatalError("Rendering failed") }
        return image
    }

    func hold(_ count: Int, every delay: Double, _ change: (Int) -> Void = { _ in }) {
        for step in 0..<count {
            change(step)
            frames.append(Frame(image: render(), delay: delay))
        }
    }

    /// Cross-fades from the last frame to the new state.
    func fade(to change: () -> Void, steps: Int = 4) {
        guard let from = frames.last?.image else { change(); return }
        change()
        let target = render()
        for step in 1...steps {
            frames.append(Frame(image: blend(from, target, CGFloat(step) / CGFloat(steps + 1)), delay: 0.05))
        }
    }

    func blend(_ first: CGImage, _ second: CGImage, _ amount: CGFloat) -> CGImage {
        let context = CGContext(data: nil, width: first.width, height: first.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: first.width, height: first.height)
        context.draw(first, in: rect)
        context.setAlpha(amount)
        context.draw(second, in: rect)
        return context.makeImage()!
    }

    // MARK: Storyboard

    func storyboard() {
        caption = "Claude Code and your builds, right in the notch"
        model.isExpanded = false
        hold(8, every: 0.22) { step in build(0.30 + Double(step) * 0.02, line: "Compiling NotchlingCore (\(30 + step * 2)%)") }

        caption = "Hover to open: music, weather, reminders and your agents"
        fade { model.isExpanded = true }
        hold(10, every: 0.22) { step in build(0.46 + Double(step) * 0.015, line: "Compiling NotchlingUI") }

        caption = "Claude asks permission: answer it from the notch"
        fade(to: { askPermission(elapsed: 0) }, steps: 3)
        hold(12, every: 0.3) { step in askPermission(elapsed: Double(step) * 0.3) }

        caption = "Allowed. Claude keeps going"
        fade(to: {
            clearPermission()
            agent("a", "PreToolUse", tool: "Bash", detail: "npm test -- --coverage", project: "Notchling")
        }, steps: 3)
        hold(8, every: 0.22) { step in build(0.62 + Double(step) * 0.045, line: "Linking Notchling") }

        caption = "Done: ✓ and a chime, so you can look away"
        fade(to: {
            build(1, line: "Finished in 42s", state: .succeeded)
            agent("a", "Stop", project: "Notchling")
        }, steps: 2)
        hold(8, every: 0.25)

        fade { model.isExpanded = false }
        caption = "notch run swift build  ·  github.com/jazlynn-choy/Notchling"
        hold(8, every: 0.25)
    }

    // MARK: Output

    func writeGIF(to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                                frames.count, nil) else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
                                        as CFDictionary)
        for frame in frames {
            CGImageDestinationAddImage(destination, frame.image,
                                       [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frame.delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}

@main
enum DemoMain {
    @MainActor
    static func main() async throws {
        _ = NSApplication.shared   // fonts and SF Symbols load through AppKit
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/demo.gif")
        let demo = Demo()
        await demo.setUp()
        demo.storyboard()
        try demo.writeGIF(to: output)

        demo.caption = "Notchling: a notch hub for developers"
        demo.model.isExpanded = true
        try demo.writePNG(demo.render(), to: output.deletingLastPathComponent().appendingPathComponent("screenshot.png"))
        print("Wrote \(output.path) (\(demo.frames.count) frames) and screenshot.png")
    }
}
