import SwiftUI
import AppKit
import Combine

enum CoordinateInput {
    static func valid(_ input: String) -> Bool {
        let cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
        let parts = cleaned.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return false }
        return lat.isFinite && lon.isFinite && abs(lat) <= 90 && abs(lon) <= 180
    }
}

@MainActor
final class LocationModel: ObservableObject {
    @Published var coordinates = ""
    @Published var devices: [String] = []
    @Published var selected = ""
    @Published var status = "Starting iPhone support…"
    @Published var busy = false
    @Published var holding = false
    @Published var stopping = false
    @Published var ready = false
    @Published var failed = false
    @Published var updates = 0
    @Published var started: Date?
    @Published var lastApplied: Date?
    @Published var ended: Date?
    @Published var showDetails = false
    @Published var now = Date()
    @Published var log = ""
    private var process: Process?
    private var outputBuffer = ""
    private var activity: NSObjectProtocol?
    private var quitPending = false
    private var currentAction = ""
    private var didRestore = false
    private var hadRestoreFailure = false
    private var clockTimer: Timer?
    let resources = Bundle.main.resourceURL!
    lazy var runtime: URL = {
        let adjacent = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".venv")
        if FileManager.default.isExecutableFile(atPath: adjacent.appendingPathComponent("bin/python").path) { return adjacent }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Cable Location/runtime")
    }()

    func appendLog(_ text: String) {
        guard !text.isEmpty else { return }
        log += text + "\n"
        if log.count > 24000 { log = String(log.suffix(20000)) }
    }

    func setup() {
        guard !busy else { return }
        if clockTimer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                DispatchQueue.main.async { self?.now = Date() }
            }
            RunLoop.main.add(timer, forMode: .common)
            clockTimer = timer
        }
        failed = false
        status = "Checking iPhone support…"
        launch(executable: URL(fileURLWithPath: "/bin/zsh"),
               arguments: [resources.appendingPathComponent("bootstrap.sh").path, runtime.path, resources.path],
               action: "setup")
    }

    func launch(executable: URL, arguments: [String], action: String) {
        guard process == nil else { return }
        currentAction = action
        busy = true
        outputBuffer = ""
        let child = Process()
        let out = Pipe(), err = Pipe()
        child.executableURL = executable
        child.arguments = arguments
        var env = ProcessInfo.processInfo.environment.filter {
            !$0.key.hasPrefix("PYMOBILEDEVICE3_") && $0.key != "USBMUXD_SOCKET_ADDRESS"
        }
        env["PYTHONUNBUFFERED"] = "1"
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        env["NO_COLOR"] = "1"
        child.environment = env
        child.standardOutput = out
        child.standardError = err
        child.standardInput = FileHandle.nullDevice
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.receive(text, json: action != "setup") }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.appendLog(text) }
        }
        child.terminationHandler = { [weak self] child in
            // Stop readability callbacks and drain buffered output before marking the action complete.
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            let remainder = out.fileHandleForReading.readDataToEndOfFile()
            let errors = err.fileHandleForReading.readDataToEndOfFile()
            DispatchQueue.main.async {
                self?.receive(String(decoding: remainder, as: UTF8.self), json: action != "setup")
                self?.appendLog(String(decoding: errors, as: UTF8.self))
                self?.finished(code: child.terminationStatus, action: action)
            }
        }
        process = child
        do { try child.run() }
        catch {
            process = nil
            busy = false
            holding = false
            stopping = false
            endActivity()
            failed = true
            status = "Could not start iPhone support: \(error.localizedDescription)"
            appendLog(status)
        }
    }

    func receive(_ text: String, json: Bool) {
        guard !text.isEmpty else { return }
        if !json { appendLog(text); return }
        outputBuffer += text
        while let newline = outputBuffer.firstIndex(of: "\n") {
            let line = String(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            guard let data = line.data(using: .utf8),
                  let item = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = item["event"] as? String else { appendLog(line); continue }
            let message = item["message"] as? String ?? ""
            switch event {
            case "devices":
                devices = item["devices"] as? [String] ?? []
                if !devices.contains(selected) { selected = devices.count == 1 ? devices[0] : "" }
                status = devices.isEmpty ? "Connect your iPhone with a USB data cable and unlock it." : "Ready. Paste coordinates to begin."
            case "applied":
                if started == nil { started = Date() }
                lastApplied = Date()
                updates += 1
                failed = false
                if !stopping { status = "Refreshing location every second" }
            case "reconnecting":
                status = "Connection interrupted — reconnecting…"
                failed = true
                appendLog(message)
            case "restored":
                didRestore = true
                hadRestoreFailure = false
                status = message
                appendLog(message)
            case "restore_failed":
                hadRestoreFailure = true
                failed = true
                status = "Restore not confirmed. Reconnect and click Restore, or restart your iPhone."
                appendLog(message)
            case "error":
                failed = true
                status = message
                appendLog(message)
            case "status":
                status = message
                appendLog(message)
            default: appendLog(message)
            }
        }
    }

    func worker(_ action: String, extra: [String] = []) {
        launch(executable: runtime.appendingPathComponent("bin/python"),
               arguments: [resources.appendingPathComponent("backend/worker.py").path, action] + extra,
               action: action)
    }

    func refreshDevices() {
        guard ready && !busy else { return }
        failed = false
        status = "Looking for USB iPhones…"
        worker("list")
    }

    func start() {
        guard !busy && ready && !selected.isEmpty else { return }
        guard CoordinateInput.valid(coordinates) else {
            failed = true
            status = "Enter latitude, longitude within −90…90 and −180…180."
            return
        }
        updates = 0
        started = nil
        ended = nil
        lastApplied = nil
        didRestore = false
        hadRestoreFailure = false
        failed = false
        holding = true
        status = "Preparing your iPhone…"
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Maintain the user-started iPhone USB location session")
        worker("hold", extra: ["--udid", selected, "--coordinates", coordinates, "--interval", "1"])
    }

    func stop() {
        guard holding && !stopping else { return }
        stopping = true
        status = "Stopping and restoring real location…"
        process?.terminate()
    }

    func restore() {
        guard !busy && ready && !selected.isEmpty else { return }
        failed = false
        hadRestoreFailure = false
        didRestore = false
        status = "Restoring real location…"
        worker("clear", extra: ["--udid", selected])
    }

    func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    func finished(code: Int32, action: String) {
        process = nil
        busy = false
        holding = false
        stopping = false
        if action == "hold" { ended = Date() }
        endActivity()
        if code != 0 {
            failed = true
            if action == "setup" { status = "Setup failed. Open Diagnostics for the error, then Retry setup." }
            else if !hadRestoreFailure && !didRestore { status = "iPhone operation failed. See Diagnostics for details." }
        } else if action == "setup" && !quitPending {
            ready = true
            refreshDevices()
        } else if action == "hold" && !didRestore && !hadRestoreFailure {
            status = "Session ended. Check Maps; use Restore if needed."
        }
        if quitPending { NSApp.reply(toApplicationShouldTerminate: true) }
    }

    func requestQuit() -> NSApplication.TerminateReply {
        guard busy else { return .terminateNow }
        quitPending = true
        if holding { stop() }
        else if currentAction == "list" || currentAction == "setup" { process?.terminate() }
        // A clear command already in progress is allowed to finish.
        return .terminateLater
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: LocationModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model?.requestQuit() ?? .terminateNow
    }
}

enum Palette {
    static let background = Color(red: 0.045, green: 0.065, blue: 0.085)
    static let surface = Color(red: 0.070, green: 0.095, blue: 0.115)
    static let raised = Color(red: 0.09, green: 0.12, blue: 0.14)
    static let mint = Color(red: 0.53, green: 0.91, blue: 0.78)
    static let ink = Color(red: 0.88, green: 0.93, blue: 0.92)
    static let muted = Color(red: 0.48, green: 0.58, blue: 0.61)
    static let line = Color.white.opacity(0.075)
}

struct CableMark: Shape {
    func path(in rect: CGRect) -> Path {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x / 100, y: rect.minY + rect.height * y / 100)
        }
        var path = Path()
        path.move(to: pt(50, 82))
        path.addCurve(to: pt(21, 40), control1: pt(41, 70), control2: pt(21, 58))
        path.addCurve(to: pt(50, 12), control1: pt(21, 24), control2: pt(34, 12))
        path.addCurve(to: pt(79, 40), control1: pt(66, 12), control2: pt(79, 24))
        path.addCurve(to: pt(50, 82), control1: pt(79, 58), control2: pt(59, 70))
        path.addLine(to: pt(50, 87))
        path.addCurve(to: pt(62, 96), control1: pt(50, 93), control2: pt(54, 96))
        path.addLine(to: pt(79, 96))
        path.addEllipse(in: CGRect(x: pt(39, 29).x, y: pt(39, 29).y,
                                   width: rect.width * 0.22, height: rect.height * 0.22))
        return path
    }
}

struct BrandMark: View {
    var size: CGFloat = 42
    var body: some View {
        CableMark().stroke(Palette.mint, style: StrokeStyle(lineWidth: size * 0.065, lineCap: .round, lineJoin: .round))
            .padding(size * 0.12).frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct PrimaryActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var stop = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(enabled ? Palette.background : Palette.muted)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(enabled ? (stop ? Color(red: 0.96, green: 0.72, blue: 0.46) : Palette.mint) : Palette.raised,
                        in: RoundedRectangle(cornerRadius: 11))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

struct SessionScope: View {
    var live: Bool
    var body: some View {
        ZStack {
            ForEach(0..<4) { index in
                Circle().stroke(Palette.mint.opacity(live ? 0.08 : 0.04), lineWidth: 1)
                    .frame(width: CGFloat(72 + index * 44), height: CGFloat(72 + index * 44))
            }
            Path { p in
                p.move(to: CGPoint(x: 0, y: 112)); p.addLine(to: CGPoint(x: 224, y: 112))
                p.move(to: CGPoint(x: 112, y: 0)); p.addLine(to: CGPoint(x: 112, y: 224))
            }.stroke(Palette.mint.opacity(0.07), style: StrokeStyle(lineWidth: 1, dash: [3, 6]))
            Circle().fill(Palette.mint.opacity(0.045)).frame(width: 110, height: 110)
            Circle().stroke(Palette.mint.opacity(0.16), lineWidth: 1).frame(width: 110, height: 110)
            BrandMark(size: 68).offset(y: -4)
            Circle().fill(live ? Palette.mint : Palette.muted).frame(width: 5, height: 5).offset(x: 75, y: -48)
            Circle().stroke(Palette.mint.opacity(0.18), lineWidth: 1).frame(width: 13, height: 13).offset(x: 75, y: -48)
        }.frame(width: 224, height: 224).accessibilityHidden(true)
    }
}

struct ContentView: View {
    @ObservedObject var model: LocationModel

    var elapsed: String {
        let end = model.ended ?? model.now
        let seconds = Int(max(0, end.timeIntervalSince(model.started ?? end)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    var validInput: Bool { CoordinateInput.valid(model.coordinates) }
    var live: Bool { model.holding && model.lastApplied != nil && !model.failed && !model.stopping }
    var sessionName: String {
        if model.stopping { return "RESTORING" }
        if model.holding { return model.failed ? "RECONNECTING" : (live ? "LIVE SESSION" : "CONNECTING") }
        return model.failed ? "NEEDS ATTENTION" : "STANDBY"
    }
    var statusColor: Color { model.failed || model.stopping ? .orange : (live ? Palette.mint : Palette.muted) }

    func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(Palette.muted)
    }

    var deviceCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                caption("01 / CONNECTION")
                Spacer()
                Button(action: model.refreshDevices) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                    .disabled(model.busy || !model.ready).help("Refresh USB devices").accessibilityLabel("Refresh USB devices")
            }
            HStack(spacing: 12) {
                Image(systemName: "iphone").font(.system(size: 25, weight: .light))
                    .foregroundStyle(model.selected.isEmpty ? Palette.muted : Palette.mint)
                    .frame(width: 40, height: 44).background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.selected.isEmpty ? "Connect your iPhone" : "Your iPhone")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Palette.ink)
                    Text(model.selected.isEmpty ? "Use a USB data cable to get started." : "USB · Developer Mode required")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
            }
            Picker("USB iPhone", selection: $model.selected) {
                Text(model.devices.isEmpty ? "No USB iPhone detected" : "Select an iPhone").tag("")
                ForEach(model.devices, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().font(.system(size: 11, design: .monospaced)).tint(Palette.mint)
                .disabled(model.busy).accessibilityLabel("USB iPhone")
        }.padding(20).background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line))
    }

    var destinationCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            caption("02 / DESTINATION")
            VStack(alignment: .leading, spacing: 7) {
                Text("Where would you like to be?").font(.system(size: 21, weight: .medium)).tracking(-0.5)
                    .foregroundStyle(Palette.ink)
                Text("One line. Any coordinate.").font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "location").font(.system(size: 12)).foregroundStyle(validInput ? Palette.mint : Palette.muted)
                    TextField("1.329152, 103.776490", text: $model.coordinates)
                        .textFieldStyle(.plain).font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Palette.ink).disabled(model.busy).onSubmit { model.start() }
                        .accessibilityLabel("Latitude, longitude")
                    if validInput { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mint).font(.system(size: 13)) }
                }.padding(14).background(Palette.background, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(validInput ? Palette.mint.opacity(0.4) : Palette.line))
                HStack {
                    Text("LATITUDE, LONGITUDE").font(.system(size: 9, weight: .medium)).tracking(1.2)
                    Spacer()
                    Text(validInput ? "Valid coordinates" : "Decimal degrees").font(.system(size: 10))
                }.foregroundStyle(validInput ? Palette.mint.opacity(0.7) : Palette.muted)
            }
            VStack(spacing: 12) {
                if model.holding {
                    Button(action: model.stop) {
                        HStack { Image(systemName: "stop.fill"); Text(model.stopping ? "Restoring location…" : "Stop & restore"); Spacer(); Image(systemName: "arrow.uturn.backward") }
                            .padding(.horizontal, 16)
                    }.buttonStyle(PrimaryActionStyle(stop: true)).disabled(model.stopping)
                } else {
                    Button(action: model.start) {
                        HStack { Text("Start location"); Spacer(); Image(systemName: "arrow.up.right") }.padding(.horizontal, 16)
                    }.buttonStyle(PrimaryActionStyle())
                        .disabled(model.busy || !model.ready || model.selected.isEmpty || !validInput)
                }
                Button(action: model.restore) {
                    Label("Restore real location", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium)).frame(height: 19)
                }.buttonStyle(.plain).foregroundStyle(Palette.muted)
                    .disabled(model.busy || !model.ready || model.selected.isEmpty)
            }.padding(.top, 2)
        }.padding(22).background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line))
    }

    var sessionPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle().fill(statusColor).frame(width: 5, height: 5)
                Text(sessionName).font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(statusColor)
                Spacer()
                if model.busy { ProgressView().controlSize(.mini).tint(Palette.mint) }
            }
            SessionScope(live: live).scaleEffect(0.94).frame(height: 210).frame(maxWidth: .infinity).padding(.vertical, 3)
            Text(elapsed).font(.system(size: 32, weight: .light, design: .monospaced)).tracking(-1.5)
                .foregroundStyle(Palette.ink).frame(maxWidth: .infinity)
            Text(model.holding ? "SESSION DURATION" : (model.updates > 0 ? "LAST SESSION" : "NO ACTIVE SESSION"))
                .font(.system(size: 8, weight: .medium)).tracking(1.5).foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity).padding(.top, 7).padding(.bottom, 24)
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Refresh").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Text("1 sec").font(.system(size: 15, weight: .medium, design: .monospaced)).foregroundStyle(Palette.ink)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 7) {
                    Text("Accepted updates").font(.system(size: 10)).foregroundStyle(Palette.muted)
                    Text("\(model.updates)").font(.system(size: 15, weight: .medium, design: .monospaced)).foregroundStyle(Palette.ink)
                }
            }.padding(.vertical, 20)
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: model.failed ? "exclamationmark.circle" : "waveform.path")
                    .foregroundStyle(statusColor).padding(.top, 1)
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.status).font(.system(size: 11)).foregroundStyle(Palette.ink.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    if let last = model.lastApplied, model.holding {
                        Text("Last update \(Int(max(0, model.now.timeIntervalSince(last))))s ago")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                }
            }.padding(.top, 18)
            Spacer(minLength: 12)
            if !model.ready && !model.busy {
                Button("Retry setup", action: model.setup).tint(Palette.mint).padding(.top, 12)
            }
        }.padding(22).frame(width: 280).frame(maxHeight: .infinity)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                BrandMark(size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cable Location").font(.system(size: 24, weight: .semibold)).tracking(-0.8).foregroundStyle(Palette.ink)
                    Text("A little change of coordinates.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer()
                Label("USB EDITION", systemImage: "cable.connector")
                    .font(.system(size: 9, weight: .medium)).tracking(1.2).foregroundStyle(Palette.muted)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .overlay(Capsule().stroke(Palette.line))
            }.padding(.bottom, 2)
            HStack(alignment: .top, spacing: 18) {
                VStack(spacing: 16) { deviceCard; destinationCard }.frame(width: 450)
                sessionPanel
            }.fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 7) {
                Image(systemName: "cable.connector").foregroundStyle(Palette.mint.opacity(0.7))
                Text("Keep your cable connected and Mac lid open.").foregroundStyle(Palette.muted)
                Spacer()
                Button { model.showDetails.toggle() } label: {
                    HStack(spacing: 5) { Text("Diagnostics"); Image(systemName: model.showDetails ? "chevron.up" : "chevron.down").font(.system(size: 8)) }
                }.buttonStyle(.plain).foregroundStyle(Palette.muted)
            }.font(.system(size: 10))
            if model.showDetails {
                ScrollView {
                    Text(model.log.isEmpty ? "No diagnostic output yet." : model.log)
                        .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.frame(height: 120).background(Palette.surface, in: RoundedRectangle(cornerRadius: 10))
            }
            Text("First time? Unlock iPhone, trust this Mac, and enable Developer Mode. Verify location in iPhone Maps.")
                .font(.system(size: 9)).foregroundStyle(Palette.muted.opacity(0.65)).padding(.top, -8)
        }
        .padding(.horizontal, 28).padding(.top, 38).padding(.bottom, 22)
        .frame(width: 804).background(Palette.background)
        .preferredColorScheme(.dark)
    }
}

@main
struct CableLocationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = LocationModel()
    init() {
        if CommandLine.arguments.contains("--self-test") {
            let valid = ["1.3291521175946346, 103.7764896710236", "-33.86, -151.2", "(1, 2)", "1 2"]
            let invalid = ["nan, 1", "91, 0", "0, 181", "1", "1,2,3", "inf, 0"]
            guard valid.allSatisfy(CoordinateInput.valid), invalid.allSatisfy({ !CoordinateInput.valid($0) }) else { exit(1) }
            print("Native coordinate validation passed.")
            exit(0)
        }
    }
    var body: some Scene {
        Window("Cable Location", id: "main") {
            ContentView(model: model).onAppear {
                delegate.model = model
                model.setup()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
