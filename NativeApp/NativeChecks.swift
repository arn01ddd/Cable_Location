import AppKit
import SwiftUI

private struct CoordinateCase: Decodable {
    let input: String
    let valid: Bool
}

@MainActor
enum NativeChecks {
    static func run() {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            guard condition() else { print("FAILED: \(message)"); exit(1) }
            count += 1
        }
        guard let index = CommandLine.arguments.firstIndex(of: "--coordinate-cases"),
              CommandLine.arguments.indices.contains(index + 1),
              let data = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1])),
              let cases = try? JSONDecoder().decode([CoordinateCase].self, from: data) else {
            print("Shared coordinate fixture is required."); exit(1)
        }
        for item in cases { check(CoordinateInput.valid(item.input) == item.valid, "Coordinate: \(item.input)") }

        let model = LocationModel(defaults: freshDefaults("checks"))
        check(model.coordinates.isEmpty && !model.canStart, "Empty launch must not allow starting")
        model.ready = true
        model.coordinates = "0, 0"
        model.selected = "missing"
        check(!model.canStart && !model.canRestore, "Unknown selection must not enable actions")
        model.receive("{\"event\":\"devices\",\"devices\":[\"phone\"]}\n", json: true)
        check(model.selected == "phone" && model.canStart && model.canRestore, "Auto-select the only USB phone")
        model.coordinates = "invalid"
        check(!model.canStart && model.canRestore, "Invalid input must not prevent real-location restoration")
        model.coordinates = "0, 0"
        model.busy = true
        check(!model.canStart && !model.canRestore, "Busy operations must disable competing actions")
        model.holding = true
        model.receive("{\"event\":\"appl", json: true)
        check(model.updates == 0, "Wait for complete worker messages")
        model.receive("ied\"}\n", json: true)
        check(model.updates == 1 && model.sessionTitle == "Live session", "Completed update starts live state")
        model.now = Date().addingTimeInterval(10)
        check(model.updateIsStale && model.sessionTitle == "Waiting for update", "Stale updates must not appear live")
        model.stopping = true
        check(model.sessionTitle == "Restoring", "Restoration overrides stale state")
        model.receive("{\"event\":\"restore_failed\",\"message\":\"Disconnected\"}\n", json: true)
        check(model.failed, "Restore failure must remain visible")
        model.receive("{\"event\":\"restored\",\"message\":\"Clear accepted\"}\n", json: true)
        check(!model.failed && model.status == "Clear accepted", "Successful retry clears failure appearance")
        model.finished(code: 0, action: "hold")
        check(!model.busy && !model.holding && !model.stopping && model.ended != nil, "Session completion resets controls")
        let elapsed = model.sessionElapsed
        model.now = Date().addingTimeInterval(300)
        check(model.sessionElapsed == elapsed, "Last session timer must freeze")
        model.receive("{\"event\":\"devices\",\"devices\":[]}\n", json: true)
        check(model.selected.isEmpty && !model.canStart, "Device removal clears selection")
        model.receive("{\"event\":\"devices\",\"devices\":[\"a\",\"b\"]}\n", json: true)
        check(model.selected.isEmpty && !model.canStart, "Multiple phones require explicit selection")

        // Map links, hemisphere notation and canonical formatting.
        let extraction: [(String, String?)] = [
            ("-33.86, 151.2", "-33.86, 151.2"),
            ("( 1.329152117, 103.776489671 )", "1.329152, 103.77649"),
            ("https://www.google.com/maps/@-33.8567844,151.213108,17z", "-33.856784, 151.213108"),
            ("https://www.google.com/maps/place/Opera/@-33.85,151.21,17z/data=!3m1!4b1!3d-33.8567844!4d151.2152967", "-33.856784, 151.215297"),
            ("https://maps.google.com/?q=40.7128,-74.0060", "40.7128, -74.006"),
            ("https://maps.apple.com/?ll=48.8584,2.2945&q=Tower", "48.8584, 2.2945"),
            ("https://maps.apple.com/?address=Paris&coordinate=48.8584%2C2.2945", "48.8584, 2.2945"),
            ("https://www.google.com/maps/search/?api=1&query=35.6586%2C139.7454", "35.6586, 139.7454"),
            ("geo:51.5007,-0.1246", "51.5007, -0.1246"),
            ("33.8568° S, 151.2153° E", "-33.8568, 151.2153"),
            ("40.7128 N 74.0060 W", "40.7128, -74.006"),
            ("-0.0000001, 0", "0, 0"),
            ("https://maps.google.com/?q=95,10", nil),
            ("https://example.com/@ab,cd", nil),
            ("91° N, 10° E", nil),
            ("Sydney Opera House", nil),
            ("", nil),
        ]
        for (input, expected) in extraction {
            check(CoordinateInput.extract(input) == expected, "Extract: \(input) → \(CoordinateInput.extract(input) ?? "nil")")
        }
        for (input, _) in extraction {
            if let found = CoordinateInput.extract(input) { check(CoordinateInput.valid(found), "Extracted value is backend-valid: \(found)") }
        }
        check(CoordinateInput.readable(-33.86, 151.2) == "33.8600° S, 151.2000° E", "Readable hemisphere format")

        // Saved places, recents and persistence.
        let storage = freshDefaults("places")
        let places = LocationModel(defaults: storage)
        check(places.places.isEmpty && places.recents.isEmpty, "Fresh storage starts empty")
        check(!places.savePlace(named: "Nowhere"), "Invalid destination cannot be saved")
        places.coordinates = "  -33.8600, 151.2000 "
        check(places.savePlace(named: "  Sydney  ") && places.places.first?.name == "Sydney", "Save trims names")
        check(places.places.first?.coordinates == "-33.86, 151.2", "Saved coordinates are canonical")
        check(places.name(for: "-33.86000, 151.2") == "Sydney", "Lookup matches equivalent coordinates")
        check(places.savePlace(named: "Harbour") && places.places.count == 1 && places.places[0].name == "Harbour",
              "Saving the same spot renames instead of duplicating")
        places.coordinates = "1, 2"
        check(places.savePlace(named: "") && places.places.first?.name == "Pin 2", "Unnamed places get a default name")
        places.coordinates = "https://maps.apple.com/?ll=48.8584,2.2945"
        check(places.point == nil, "Raw links are not a destination until extracted")
        places.use("https://maps.apple.com/?ll=48.8584,2.2945")
        check(places.coordinates == "48.8584, 2.2945", "Using a link fills canonical coordinates")
        places.pick(lat: 10.123456789, lon: -20.5)
        check(places.coordinates == "10.123457, -20.5", "Map picks are rounded to six decimals")
        places.pick(lat: 95, lon: 0)
        check(places.coordinates == "10.123457, -20.5", "Out-of-range map picks are ignored")
        places.busy = true
        places.use("0, 0")
        check(places.coordinates == "10.123457, -20.5", "Destinations are locked while busy")
        places.busy = false
        let board = NSPasteboard(name: NSPasteboard.Name("cablelocation.checks.\(UUID().uuidString)"))
        board.clearContents(); board.setString("https://www.google.com/maps/@35.6586,139.7454,15z", forType: .string)
        check(places.pasteFromClipboard(board) && places.coordinates == "35.6586, 139.7454", "Paste extracts map links")
        board.clearContents(); board.setString("not a place", forType: .string)
        check(!places.pasteFromClipboard(board) && places.coordinates == "35.6586, 139.7454" &&
              places.status.contains("clipboard"), "Unusable clipboard keeps the destination and explains why")
        board.releaseGlobally()
        places.ready = true
        places.receive("{\"event\":\"devices\",\"devices\":[\"phone\"]}\n", json: true)
        for value in ["1, 1", "2, 2", "3, 3", "4, 4", "5, 5", "6, 6", "2, 2.0"] {
            places.coordinates = value
            places.start()
            places.finished(code: 0, action: "hold")
        }
        check(places.recents == ["2, 2", "6, 6", "5, 5", "4, 4", "3, 3"], "Recents are deduplicated, newest first, capped at five")
        places.removePlace(places.places[0])
        check(places.places.map(\.name) == ["Harbour"], "Remove deletes only the chosen place")
        let reloaded = LocationModel(defaults: storage)
        check(reloaded.places == places.places && reloaded.recents == places.recents, "Places and recents persist")
        check(reloaded.coordinates == "2, 2", "Last destination is restored on launch")
        reloaded.clearRecents()
        check(LocationModel(defaults: storage).recents.isEmpty, "Clearing recents persists")
        storage.set(Data("garbage".utf8), forKey: "savedPlaces")
        storage.set(["bad", "7, 7"], forKey: "recentCoordinates")
        let corrupt = LocationModel(defaults: storage)
        check(corrupt.places.isEmpty && corrupt.recents == ["7, 7"], "Corrupt storage is ignored safely")

        // Live state requires a recent accepted update.
        let live = LocationModel(defaults: freshDefaults("live"))
        live.holding = true
        check(!live.isLive && live.lastUpdateText == "—", "Connecting is not live")
        live.lastApplied = Date(); live.now = Date()
        check(live.isLive, "Recent update is live")
        live.failed = true
        check(!live.isLive, "Reconnecting is not live")

        let textPairs: [(UInt32, UInt32)] = [
            (Palette.inkHex, Palette.surfaceHex), (Palette.inkHex, Palette.canvasHex),
            (Palette.inkHex, Palette.sidebarHex), (Palette.inkHex, Palette.raisedHex),
            (Palette.inkHex, Palette.inputHex), (Palette.inkHex, Palette.selectionHex),
            (Palette.inkHex, Palette.secondaryHex), (Palette.inkHex, Palette.warningBackgroundHex),
            (Palette.mutedHex, Palette.surfaceHex), (Palette.mutedHex, Palette.canvasHex),
            (Palette.mutedHex, Palette.sidebarHex), (Palette.mutedHex, Palette.raisedHex),
            (Palette.mutedHex, Palette.inputHex), (Palette.mutedHex, Palette.disabledHex),
            (Palette.mutedHex, Palette.selectionHex), (Palette.mutedHex, Palette.warningBackgroundHex),
            (Palette.accentHex, Palette.softHex), (Palette.accentHex, Palette.surfaceHex),
            (Palette.accentHex, Palette.sidebarHex), (Palette.accentHex, Palette.selectionHex),
            (Palette.accentHex, Palette.canvasHex), (Palette.mutedHex, Palette.softHex),
            (Palette.buttonInkHex, Palette.accentHex), (Palette.buttonInkHex, Palette.warningHex),
            (Palette.liveHex, Palette.liveBackgroundHex), (Palette.liveHex, Palette.inputHex),
            (Palette.warningHex, Palette.warningBackgroundHex), (Palette.warningHex, Palette.surfaceHex),
            (Palette.dangerHex, Palette.surfaceHex), (Palette.dangerHex, Palette.inputHex)
        ]
        for (foreground, background) in textPairs {
            check(contrast(foreground, background) >= 4.5,
                  String(format: "Text contrast %06X on %06X must reach 4.5:1", foreground, background))
        }
        for background in [Palette.surfaceHex, Palette.inputHex, Palette.secondaryHex, Palette.disabledHex] {
            check(contrast(Palette.controlLineHex, background) >= 3, String(format: "Control boundary on %06X must reach 3:1", background))
        }
        check(contrast(Palette.accentHex, Palette.inputHex) >= 3, "Input focus contrast must reach 3:1")
        check(contrast(Palette.dangerHex, Palette.inputHex) >= 3, "Invalid-input boundary must reach 3:1")
        print("Native checks passed: \(count) assertions, including \(cases.count) shared coordinate cases and text contrast.")
    }

    static func freshDefaults(_ name: String) -> UserDefaults {
        let suite = "local.cablelocation.\(name).\(ProcessInfo.processInfo.processIdentifier)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ rgb: UInt32) -> Double {
            let c = [16, 8, 0].map { shift -> Double in
                let channel = Double((rgb >> shift) & 255) / 255
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            }
            return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

@MainActor
enum NativePreviews {
    static func render(to directory: String) throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for name in ["empty", "ready", "active", "error", "compact"] {
            let model = LocationModel(defaults: NativeChecks.freshDefaults("preview-\(name)"))
            model.ready = true
            model.status = "Connect your iPhone with a USB data cable and unlock it."
            if name != "empty" {
                model.devices = ["USB-IPHONE-PREVIEW"]
                model.selected = model.devices[0]
                model.status = "Ready. Choose a destination to begin."
            }
            if name == "ready" || name == "active" {
                for (title, value) in [("Office", "37.33182, -122.03118"), ("Harbour", "-33.856784, 151.215297")] {
                    model.coordinates = value
                    model.savePlace(named: title)
                }
                model.recents = ["-33.856784, 151.215297", "35.6586, 139.7454", "48.8584, 2.2945"]
                model.coordinates = name == "ready" ? "35.6586, 139.7454" : ""
            }
            if name == "active" {
                model.coordinates = "-33.860000, 151.200000"
                model.busy = true
                model.holding = true
                model.started = Date().addingTimeInterval(-42)
                model.lastApplied = Date()
                model.updates = 42
                model.status = "Refreshing location every second."
            }
            if name == "error" {
                model.coordinates = "91, 200"
                model.failed = true
                model.showDetails = true
                model.status = "Restore not confirmed. Reconnect and click Restore, or restart your iPhone."
                model.log = "USB connection interrupted.\nRestore command failed: device disconnected.\nReconnect your iPhone, unlock it, then choose Restore real location."
            }
            let size = NSSize(width: name == "compact" ? 960 : 1060,
                              height: name == "error" ? 1180 : (name == "compact" ? 760 : 980))
            let host = NSHostingView(rootView: ContentView(model: model, showsMap: false))
            let rect = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.frame = rect
            window.displayIfNeeded()
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                throw NSError(domain: "Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: "No bitmap for \(name)"])
            }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "Preview", code: 2, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
            }
            try png.write(to: output.appendingPathComponent("\(name).png"))
            window.close()
            print("Rendered \(name): \(Int(size.width)) × \(Int(size.height))")
        }
    }
}
