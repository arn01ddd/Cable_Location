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

        let model = LocationModel()
        check(model.coordinates.isEmpty && !model.canStart, "Empty launch must not allow starting")
        model.ready = true
        model.coordinates = "0, 0"
        model.selected = "missing"
        check(!model.canStart && !model.canRestore, "Unknown selection must not enable actions")
        model.receive("{\"event\":\"devices\",\"devices\":[\"phone\"]}\n", json: true)
        check(model.selected == "phone" && model.canStart && model.canRestore, "Auto-select the only USB phone")
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

        let textPairs: [(UInt32, UInt32)] = [
            (Palette.inkHex, 0xFFFFFF), (Palette.mutedHex, Palette.canvasHex),
            (Palette.mutedHex, 0xFFFFFF), (Palette.accentHex, 0xE8F2EC),
            (Palette.sidebarMutedHex, Palette.sidebarHex), (0xADF0CE, Palette.sidebarHex),
            (0xFFFFFF, Palette.inkHex), (Palette.warningHex, 0xFFF2DD),
            (Palette.dangerHex, 0xFFFFFF), (Palette.mutedHex, 0xE3EAE5)
        ]
        for (foreground, background) in textPairs {
            check(contrast(foreground, background) >= 4.5, "Normal text contrast must reach 4.5:1")
        }
        print("Native checks passed: \(count) assertions, including \(cases.count) shared coordinate cases and text contrast.")
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
            let model = LocationModel()
            model.ready = true
            model.status = "Connect your iPhone with a USB data cable and unlock it."
            if name != "empty" {
                model.devices = ["USB-IPHONE-PREVIEW"]
                model.selected = model.devices[0]
                model.status = "Ready. Paste coordinates to begin."
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
            let size = NSSize(width: name == "compact" ? 940 : 1000,
                              height: name == "error" ? 980 : (name == "compact" ? 740 : 780))
            let host = NSHostingView(rootView: ContentView(model: model))
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
