import SwiftUI
import AppKit
import Combine

enum CoordinateInput {
    static func parse(_ input: String) -> (lat: Double, lon: Double)? {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("(") && cleaned.hasSuffix(")") {
            cleaned.removeFirst()
            cleaned.removeLast()
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let parts = cleaned.contains(",")
            ? cleaned.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            : cleaned.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let decimal = #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#
        guard parts.allSatisfy({ $0.range(of: decimal, options: .regularExpression) != nil }) else { return nil }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        guard lat.isFinite && lon.isFinite && abs(lat) <= 90 && abs(lon) <= 180 else { return nil }
        return (lat, lon)
    }

    static func valid(_ input: String) -> Bool { parse(input) != nil }

    /// Canonical "lat, lon" text with six decimals (about 0.1 m), accepted by the backend.
    static func format(_ lat: Double, _ lon: Double) -> String {
        func clean(_ value: Double) -> String {
            var text = String(format: "%.6f", value)
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
            return text == "-0" ? "0" : text
        }
        return "\(clean(lat)), \(clean(lon))"
    }

    /// Human-readable hemisphere form, e.g. "33.8600° S, 151.2000° E".
    static func readable(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.4f° %@, %.4f° %@", abs(lat), lat < 0 ? "S" : "N", abs(lon), lon < 0 ? "W" : "E")
    }

    /// Extracts coordinates from plain text, hemisphere notation, or Apple/Google Maps and geo: links.
    static func extract(_ text: String) -> String? {
        let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.count <= 4096 else { return nil }
        if let pair = parse(raw) { return format(pair.lat, pair.lon) }
        let decoded = (raw.removingPercentEncoding ?? raw).replacingOccurrences(of: "+", with: " ")
        let number = #"([+-]?[0-9]{1,3}(?:\.[0-9]+)?)"#
        let patterns = [
            #"!3d"# + number + #"!4d"# + number,
            #"@"# + number + #"\s*,\s*"# + number,
            #"[?&](?:q|ll|sll|daddr|saddr|center|query|destination|coordinate)="# + number + #"\s*,\s*"# + number,
            #"^geo:"# + number + #"\s*,\s*"# + number,
        ]
        for pattern in patterns {
            if let pair = capture(pattern, in: decoded), let found = parse("\(pair.0), \(pair.1)") {
                return format(found.lat, found.lon)
            }
        }
        let hemisphere = #"^([0-9]{1,2}(?:\.[0-9]+)?)\s*°?\s*([NSns])[\s,]+([0-9]{1,3}(?:\.[0-9]+)?)\s*°?\s*([EWew])$"#
        if let regex = try? NSRegularExpression(pattern: hemisphere),
           let match = regex.firstMatch(in: decoded, range: NSRange(decoded.startIndex..., in: decoded)), match.numberOfRanges == 5 {
            let group = { (i: Int) in String(decoded[Range(match.range(at: i), in: decoded)!]) }
            if var lat = Double(group(1)), var lon = Double(group(3)) {
                if group(2).uppercased() == "S" { lat = -lat }
                if group(4).uppercased() == "W" { lon = -lon }
                if let found = parse("\(lat), \(lon)") { return format(found.lat, found.lon) }
            }
        }
        return nil
    }

    private static func capture(_ pattern: String, in text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 3,
              let a = Range(match.range(at: 1), in: text), let b = Range(match.range(at: 2), in: text) else { return nil }
        return (String(text[a]), String(text[b]))
    }
}

struct SavedPlace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var coordinates: String
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
    @Published var places: [SavedPlace] = []
    @Published var recents: [String] = []
    private let defaults: UserDefaults
    static let maxPlaces = 30
    static let maxRecents = 5
    private var process: Process?
    private var outputBuffer = ""
    private var activity: NSObjectProtocol?
    private var quitPending = false
    private var currentAction = ""
    private var didRestore = false
    private var hadRestoreFailure = false
    private var clockTimer: Timer?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "savedPlaces"),
           let stored = try? JSONDecoder().decode([SavedPlace].self, from: data) {
            places = stored.filter { CoordinateInput.valid($0.coordinates) }
        }
        recents = (defaults.stringArray(forKey: "recentCoordinates") ?? []).filter(CoordinateInput.valid)
        if let last = defaults.string(forKey: "lastCoordinates"), CoordinateInput.valid(last) { coordinates = last }
    }

    var point: (lat: Double, lon: Double)? { CoordinateInput.parse(coordinates) }
    var hasDevice: Bool { !selected.isEmpty && devices.contains(selected) }
    var canStart: Bool { ready && !busy && hasDevice && CoordinateInput.valid(coordinates) }
    var canRestore: Bool { ready && !busy && hasDevice }
    var isLive: Bool { holding && !stopping && !failed && !updateIsStale && lastApplied != nil }
    var lastUpdateText: String {
        guard let lastApplied else { return "—" }
        return "\(Int(max(0, now.timeIntervalSince(lastApplied))))s ago"
    }
    var updateIsStale: Bool {
        guard holding, let lastApplied else { return false }
        return now.timeIntervalSince(lastApplied) > 5
    }
    var sessionTitle: String {
        if stopping { return "Restoring" }
        if holding {
            if failed { return "Reconnecting" }
            if updateIsStale { return "Waiting for update" }
            return lastApplied == nil ? "Connecting" : "Live session"
        }
        if failed { return "Needs attention" }
        if !ready { return busy ? "Setting up" : "Setup needed" }
        if busy { return "Working" }
        return hasDevice ? "Ready" : "No device"
    }
    var sessionElapsed: String {
        let end = ended ?? now
        let seconds = Int(max(0, end.timeIntervalSince(started ?? end)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
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

    // MARK: Destinations

    func use(_ text: String) {
        guard !busy, let normalized = CoordinateInput.extract(text) else { return }
        coordinates = normalized
    }

    func pick(lat: Double, lon: Double) {
        guard !busy, CoordinateInput.valid("\(lat), \(lon)") else { return }
        coordinates = CoordinateInput.format(lat, lon)
    }

    @discardableResult
    func pasteFromClipboard(_ pasteboard: NSPasteboard = .general) -> Bool {
        guard !busy else { return false }
        guard let text = pasteboard.string(forType: .string), let normalized = CoordinateInput.extract(text) else {
            status = "The clipboard has no coordinates or map link."
            return false
        }
        coordinates = normalized
        return true
    }

    func name(for coordinates: String) -> String? {
        guard let key = CoordinateInput.extract(coordinates) else { return nil }
        return places.first { $0.coordinates == key }?.name
    }

    @discardableResult
    func savePlace(named name: String) -> Bool {
        guard let key = CoordinateInput.extract(coordinates) else { return false }
        var title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { title = "Pin \(places.count + 1)" }
        title = String(title.prefix(60))
        if let index = places.firstIndex(where: { $0.coordinates == key }) {
            places[index].name = title
        } else {
            places.insert(SavedPlace(name: title, coordinates: key), at: 0)
            if places.count > Self.maxPlaces { places.removeLast(places.count - Self.maxPlaces) }
        }
        persistPlaces()
        return true
    }

    func removePlace(_ place: SavedPlace) {
        places.removeAll { $0.id == place.id }
        persistPlaces()
    }

    func clearRecents() {
        recents = []
        defaults.set(recents, forKey: "recentCoordinates")
    }

    private func persistPlaces() {
        if let data = try? JSONEncoder().encode(places) { defaults.set(data, forKey: "savedPlaces") }
    }

    private func remember(_ coordinates: String) {
        guard let key = CoordinateInput.extract(coordinates) else { return }
        recents.removeAll { $0 == key }
        recents.insert(key, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
        defaults.set(recents, forKey: "recentCoordinates")
        defaults.set(key, forKey: "lastCoordinates")
    }

    // MARK: Backend

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
        didRestore = false
        hadRestoreFailure = false
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
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
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
                status = devices.isEmpty ? "Connect your iPhone with a USB data cable and unlock it." : "Ready. Choose a destination to begin."
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
                failed = false
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
        guard !busy && ready && hasDevice else { return }
        guard CoordinateInput.valid(coordinates) else {
            failed = true
            status = "Enter latitude, longitude within −90…90 and −180…180."
            return
        }
        if let normalized = CoordinateInput.extract(coordinates) { coordinates = normalized }
        remember(coordinates)
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
        guard canRestore else { return }
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

@main
struct CableLocationApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = LocationModel()
    init() {
        if CommandLine.arguments.contains("--self-test") {
            NativeChecks.run()
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
           CommandLine.arguments.indices.contains(index + 1) {
            do { try NativePreviews.render(to: CommandLine.arguments[index + 1]) }
            catch { print("Preview rendering failed: \(error)"); exit(1) }
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
        .windowResizability(.automatic)
        .defaultSize(width: 1000, height: 780)
        .defaultPosition(.center)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
