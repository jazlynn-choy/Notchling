import Foundation
import NotchlingActivity

// `notch`: show what your terminal is doing in the MacBook notch (needs Notchling running).
//
//   notch run npm run build        progress pill while it runs, ✓/✗ and a chime when it ends
//   npm test | notch               same, for a pipe
//   notch "Deploy finished"        a one-off message
//   notch done "Backup complete"   / notch fail "Backup failed"
//
// Rules: output passes through untouched, `notch run` exits with the command's own status,
// and nothing Notchling-related (a missing folder, a write error) can make the command fail.

let usage = """
usage: notch run [--title TEXT] [--] COMMAND [ARGS...]
       COMMAND | notch [--title TEXT]
       notch [done|fail] MESSAGE

Shows a command's progress in the notch (Notchling must be running).
  run      run COMMAND, show its latest output line and any "45%" or "3/10" progress,
           then ✓ or ✗ with how long it took. Exits with COMMAND's exit status.
  done     show MESSAGE with a ✓       fail   show MESSAGE with a ✗
  --title  the name shown in the notch (default: the command)

Note: COMMAND's output goes through a pipe, so tools that only colour a real terminal
may print plainly.
"""

/// Collects output from any thread and publishes it to the notch a few times a second.
final class Reporter: @unchecked Sendable {
    private let folder = ActivityFolder()
    private let lock = NSLock()
    private var activity: Activity
    private var dirty = true
    private var lineBuffer = ""
    private var lastWrite = Date.distantPast

    init(title: String) {
        activity = Activity(title: title, state: .running)
    }

    func consume(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        lock.withLock {
            lineBuffer += text
            // Progress bars redraw with \r, so treat it like a line break.
            let lines = lineBuffer.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" }
            lineBuffer = String(lines.last ?? "")
            for raw in lines.dropLast() {
                let line = OutputParser.stripANSI(String(raw))
                guard !line.isEmpty else { continue }
                activity.detail = String(line.prefix(120))
                if let progress = OutputParser.progress(in: line) { activity.progress = progress }
                dirty = true
            }
        }
    }

    /// Writes if something changed (at most every 0.25 s), and at least every 10 s so the
    /// app can tell a quiet build from a dead one.
    func flush(force: Bool = false) {
        lock.withLock {
            let now = Date()
            guard force || (dirty && now.timeIntervalSince(lastWrite) >= 0.25) || now.timeIntervalSince(lastWrite) >= 10
            else { return }
            activity.updatedAt = now
            try? folder.write(activity)
            dirty = false
            lastWrite = now
        }
    }

    func finish(_ state: Activity.State, detail: String) {
        lock.withLock {
            activity.state = state
            activity.detail = detail
            if state == .succeeded { activity.progress = 1 }
            dirty = true
        }
        flush(force: true)
    }
}

/// Reads `handle` to the end on a background thread, copying everything to `echo`.
func pump(_ handle: FileHandle, to echo: FileHandle, reporter: Reporter, group: DispatchGroup) {
    group.enter()
    Thread.detachNewThread {
        while true {
            let data = handle.availableData
            if data.isEmpty { break }
            echo.write(data)
            reporter.consume(data)
        }
        group.leave()
    }
}

func startTicker(_ reporter: Reporter) -> DispatchSourceTimer {
    let timer = DispatchSource.makeTimerSource(queue: .global())
    timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
    timer.setEventHandler { reporter.flush() }
    timer.resume()
    return timer
}

func run(_ command: [String], title: String?) -> Int32 {
    let reporter = Reporter(title: title ?? String(command.joined(separator: " ").prefix(40)))
    reporter.flush(force: true)
    let started = Date()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command
    process.standardInput = FileHandle.standardInput
    let out = Pipe(), err = Pipe()
    process.standardOutput = out
    process.standardError = err

    // Ctrl-C reaches the command (same process group) and stops it; `notch` itself stays
    // alive just long enough to report "Interrupted". A handler, unlike SIG_IGN, isn't
    // inherited by the command, so the command still reacts to Ctrl-C normally.
    signal(SIGINT) { _ in }

    do {
        try process.run()
    } catch {
        reporter.finish(.failed, detail: "Couldn't start: \(error.localizedDescription)")
        FileHandle.standardError.write(Data("notch: \(error.localizedDescription)\n".utf8))
        return 127
    }
    let group = DispatchGroup()
    pump(out.fileHandleForReading, to: .standardOutput, reporter: reporter, group: group)
    pump(err.fileHandleForReading, to: .standardError, reporter: reporter, group: group)
    let ticker = startTicker(reporter)
    process.waitUntilExit()
    group.wait()
    ticker.cancel()

    let took = OutputParser.duration(Date().timeIntervalSince(started))
    let status = process.terminationStatus
    if process.terminationReason == .uncaughtSignal {
        reporter.finish(.failed, detail: status == SIGINT ? "Interrupted after \(took)" : "Stopped after \(took)")
        return 128 + status
    }
    if status == 0 {
        reporter.finish(.succeeded, detail: "Finished in \(took)")
    } else if status == 127 {
        reporter.finish(.failed, detail: "Command not found")
    } else {
        reporter.finish(.failed, detail: "Failed (exit \(status)) after \(took)")
    }
    return status
}

func stream(title: String?) -> Int32 {
    let reporter = Reporter(title: title ?? "Output")
    reporter.flush(force: true)
    let started = Date()
    let group = DispatchGroup()
    pump(.standardInput, to: .standardOutput, reporter: reporter, group: group)
    let ticker = startTicker(reporter)
    group.wait()
    ticker.cancel()
    // A pipe can't see the exit status of the command before it; use `notch run` for ✓/✗.
    reporter.finish(.info, detail: "Done in \(OutputParser.duration(Date().timeIntervalSince(started)))")
    return 0
}

func message(_ text: String, state: Activity.State) -> Int32 {
    guard !text.isEmpty else {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        return 64
    }
    try? ActivityFolder().write(Activity(title: text, state: state))
    return 0
}

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
var title: String?
if let index = arguments.firstIndex(where: { $0 == "--title" || $0 == "-t" }), index + 1 < arguments.count {
    title = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
}

let exitCode: Int32
switch arguments.first {
case "-h", "--help", "help":
    print(usage)
    exitCode = 0
case "run":
    var command = Array(arguments.dropFirst())
    if command.first == "--" { command.removeFirst() }
    if command.isEmpty {
        FileHandle.standardError.write(Data((usage + "\n").utf8))
        exitCode = 64
    } else {
        exitCode = run(command, title: title)
    }
case "done":
    exitCode = message(arguments.dropFirst().joined(separator: " "), state: .succeeded)
case "fail":
    exitCode = message(arguments.dropFirst().joined(separator: " "), state: .failed)
case nil where isatty(STDIN_FILENO) == 0:
    exitCode = stream(title: title)
case nil:
    print(usage)
    exitCode = 64
default:
    exitCode = message(arguments.joined(separator: " "), state: .info)
}
exit(exitCode)
