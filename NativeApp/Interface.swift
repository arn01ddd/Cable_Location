import SwiftUI
import AppKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

enum Palette {
    static let canvasHex: UInt32 = 0x090F1C
    static let surfaceHex: UInt32 = 0x111C2E
    static let inputHex: UInt32 = 0x0B1424
    static let inkHex: UInt32 = 0xEDF3FF
    static let mutedHex: UInt32 = 0xA7B7D0
    static let accentHex: UInt32 = 0x8FB8FF
    static let sidebarHex: UInt32 = 0x060B14
    static let sidebarMutedHex: UInt32 = 0x9DAFCA
    static let sidebarCardHex: UInt32 = 0x0E1928
    static let sidebarSelectionHex: UInt32 = 0x152843
    static let softHex: UInt32 = 0x162A48
    static let secondaryHex: UInt32 = 0x15243A
    static let disabledHex: UInt32 = 0x1C293D
    static let buttonInkHex: UInt32 = 0x081426
    static let controlLineHex: UInt32 = 0x61799B
    static let warningHex: UInt32 = 0xFFD28A
    static let warningBackgroundHex: UInt32 = 0x322716
    static let dangerHex: UInt32 = 0xFF9CAF
    static let canvas = Color(hex: canvasHex)
    static let surface = Color(hex: surfaceHex)
    static let input = Color(hex: inputHex)
    static let ink = Color(hex: inkHex)
    static let muted = Color(hex: mutedHex)
    static let accent = Color(hex: accentHex)
    static let sidebar = Color(hex: sidebarHex)
    static let sidebarMuted = Color(hex: sidebarMutedHex)
    static let sidebarCard = Color(hex: sidebarCardHex)
    static let sidebarSelection = Color(hex: sidebarSelectionHex)
    static let line = Color(hex: 0x293B55)
    static let controlLine = Color(hex: controlLineHex)
    static let soft = Color(hex: softHex)
    static let secondary = Color(hex: secondaryHex)
    static let disabled = Color(hex: disabledHex)
    static let buttonInk = Color(hex: buttonInkHex)
    static let warning = Color(hex: warningHex)
    static let danger = Color(hex: dangerHex)
    static let warningBackground = Color(hex: warningBackgroundHex)
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
    var size: CGFloat = 34
    var body: some View {
        CableMark().stroke(Palette.accent, style: StrokeStyle(lineWidth: size * 0.065,
                                                           lineCap: .round, lineJoin: .round))
            .padding(size * 0.12).frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct ActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var primary = true
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(enabled ? (primary ? Palette.buttonInk : Palette.ink) : Palette.muted)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(enabled && primary ? (destructive ? Palette.warning : Palette.accent) :
                            (primary ? Palette.disabled : Palette.secondary),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(primary ? Color.clear : (enabled ? Palette.controlLine : Palette.line)))
            .opacity(configuration.isPressed ? 0.78 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatusPill: View {
    let text: String
    var color = Palette.accent
    var background = Palette.soft
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(text).font(.system(size: 12, weight: .semibold))
        }.foregroundStyle(color).padding(.horizontal, 12).padding(.vertical, 8)
            .background(background, in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

struct ContentView: View {
    @ObservedObject var model: LocationModel
    @FocusState private var coordinateFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var validInput: Bool { CoordinateInput.valid(model.coordinates) }
    private var invalidInput: Bool { !model.coordinates.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !validInput }
    private var attention: Bool { model.failed || model.stopping || model.updateIsStale }
    private var statusColor: Color {
        attention ? Palette.warning : (model.hasDevice && model.ready ? Palette.accent : Palette.muted)
    }
    private var statusBackground: Color { attention ? Palette.warningBackground : Palette.soft }

    private func eyebrow(_ text: String, color: Color = Palette.muted) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).tracking(1.7).foregroundStyle(color)
    }

    private func guide(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text(number).font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.accent).frame(width: 24, height: 24)
                .overlay(Circle().stroke(Color.white.opacity(0.18)))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                Text(detail).font(.system(size: 12)).lineSpacing(3).foregroundStyle(Palette.sidebarMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cable Location").font(.system(size: 17, weight: .semibold)).tracking(-0.5).foregroundStyle(.white)
                    Text("A change of coordinates.").font(.system(size: 12)).foregroundStyle(Palette.sidebarMuted)
                }
            }.padding(.bottom, 36)

            HStack(spacing: 10) {
                Image(systemName: "location.fill").font(.system(size: 14))
                Text("Location workspace").font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }.foregroundStyle(Palette.accent).padding(13)
                .background(Palette.sidebarSelection, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                eyebrow("YOUR DEVICE", color: Palette.sidebarMuted)
                Spacer()
                Button(action: model.refreshDevices) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(.white)
                    .disabled(model.busy || !model.ready).help("Refresh USB devices")
                    .accessibilityLabel("Refresh USB devices").keyboardShortcut("r", modifiers: .command)
            }.padding(.top, 29).padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    Image(systemName: "iphone").font(.system(size: 27, weight: .light))
                        .foregroundStyle(Palette.accent).frame(width: 38, height: 43)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.hasDevice ? "iPhone selected" : "Connect an iPhone")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        Label(model.hasDevice ? "USB device detected" : "USB connection", systemImage: "cable.connector")
                            .font(.system(size: 12)).foregroundStyle(Palette.sidebarMuted)
                    }
                }
                if model.devices.count > 1 {
                    Picker("USB iPhone", selection: $model.selected) {
                        Text("Select an iPhone").tag("")
                        ForEach(model.devices, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).colorScheme(.dark)
                        .disabled(model.busy).accessibilityLabel("USB iPhone")
                } else if model.hasDevice {
                    Text(model.selected).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.sidebarMuted).lineLimit(1).truncationMode(.middle)
                        .help(model.selected).textSelection(.enabled)
                } else {
                    Text("Connect a data cable, unlock your iPhone, then refresh.")
                        .font(.system(size: 12)).lineSpacing(3).foregroundStyle(Palette.sidebarMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.sidebarCard, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10)))

            Spacer(minLength: 32)
            eyebrow("BEFORE YOU START", color: Palette.sidebarMuted).padding(.bottom, 18)
            VStack(alignment: .leading, spacing: 18) {
                guide("1", "Connect & trust", "Unlock your iPhone and trust this Mac.")
                guide("2", "Enable Developer Mode", "Settings → Privacy & Security.")
                guide("3", "Verify in Maps", "Check the blue dot on your iPhone.")
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1).padding(.top, 28).padding(.bottom, 18)
            Label("Made for a wired connection", systemImage: "cable.connector")
                .font(.system(size: 12)).foregroundStyle(Palette.sidebarMuted)
        }.padding(.horizontal, 22).padding(.top, 46).padding(.bottom, 24)
            .frame(width: 272).frame(maxHeight: .infinity).background(Palette.sidebar)
    }

    private var destination: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Destination", systemImage: "mappin.and.ellipse")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                Text("DECIMAL DEGREES").font(.system(size: 12, weight: .semibold))
                    .tracking(1).foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "location").font(.system(size: 18))
                        .foregroundStyle(coordinateFocused ? Palette.accent : Palette.muted).accessibilityHidden(true)
                    TextField("", text: $model.coordinates)
                        .textFieldStyle(.plain).font(.system(size: 17, design: .monospaced))
                        .foregroundStyle(Palette.ink).focused($coordinateFocused).disabled(model.busy)
                        .onSubmit { model.start() }.accessibilityLabel("Destination latitude and longitude")
                        .overlay(alignment: .leading) {
                            if model.coordinates.isEmpty {
                                Text("Latitude, Longitude").font(.system(size: 17, design: .monospaced))
                                    .foregroundStyle(Palette.muted).allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                        .help("Decimal degrees, latitude first. Use a minus sign for south or west.")
                    if validInput {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                            .accessibilityLabel("Valid coordinates")
                    }
                }.padding(18).background(Palette.input, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .stroke(coordinateFocused ? Palette.accent : (invalidInput ? Palette.danger : Palette.controlLine),
                                lineWidth: coordinateFocused ? 2 : 1))
                Text(invalidInput ? "Enter a valid latitude (−90…90) and longitude (−180…180)." :
                     "Latitude first. Use a minus sign for south or west.")
                    .font(.system(size: 12)).foregroundStyle(invalidInput ? Palette.danger : Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                if model.holding {
                    Button(action: model.stop) {
                        Label(model.stopping ? "Restoring…" : "Stop & restore", systemImage: "stop.fill")
                    }.buttonStyle(ActionStyle(destructive: true)).disabled(model.stopping)
                } else {
                    Button(action: model.start) {
                        HStack(spacing: 12) { Text("Start location"); Image(systemName: "arrow.up.right") }
                    }.buttonStyle(ActionStyle()).disabled(!model.canStart)
                        .keyboardShortcut(.return, modifiers: .command)
                }
                Button(action: model.restore) {
                    Label("Restore real location", systemImage: "arrow.uturn.backward")
                }.buttonStyle(ActionStyle(primary: false)).disabled(!model.canRestore)
                    .help("Request a return to the iPhone’s real location, then verify in Maps.")
            }
            if !model.ready && !model.busy {
                Button("Retry iPhone setup", action: model.setup).buttonStyle(.link).tint(Palette.accent)
            }
        }.padding(24).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))
            .shadow(color: Color.black.opacity(0.16), radius: 16, y: 5)
    }

    private func metric(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(value).font(.system(size: 25, weight: .medium, design: .monospaced)).tracking(-1)
                .foregroundStyle(Palette.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            Text(name).font(.system(size: 12)).foregroundStyle(Palette.muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var session: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(model.holding ? "Current session" : (model.updates > 0 ? "Last session" : "Session overview"))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Palette.ink)
                Spacer()
                if model.holding, let last = model.lastApplied {
                    Text("Updated \(Int(max(0, model.now.timeIntervalSince(last))))s ago")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
            }
            HStack(spacing: 20) {
                metric("Duration", model.sessionElapsed)
                Rectangle().fill(Palette.line).frame(width: 1, height: 40)
                metric("Refresh interval", "1 sec")
                Rectangle().fill(Palette.line).frame(width: 1, height: 40)
                metric("Accepted updates", "\(model.updates)")
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: attention ? "exclamationmark.circle.fill" :
                        (model.holding ? "waveform.path" : "info.circle"))
                    .foregroundStyle(statusColor).frame(width: 18).padding(.top, 1).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.updateIsStale && !model.stopping && !model.failed ?
                         "No recent update. Check the cable and unlock your iPhone." : model.status)
                        .font(.system(size: 13)).foregroundStyle(Palette.ink).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Text("Service activity only. Verify the location in iPhone Maps.")
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if model.busy { ProgressView().controlSize(.small).tint(Palette.accent) }
            }
        }.padding(24).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Keep your cable connected and Mac lid open.", systemImage: "cable.connector")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                Spacer(minLength: 8)
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { model.showDetails.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text("Diagnostics")
                        Image(systemName: model.showDetails ? "chevron.up" : "chevron.down").font(.system(size: 10))
                    }.font(.system(size: 12, weight: .medium)).padding(.vertical, 8)
                }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                    .accessibilityLabel(model.showDetails ? "Hide diagnostics" : "Show diagnostics")
            }
            if model.showDetails {
                ScrollView {
                    Text(model.log.isEmpty ? "No diagnostic messages yet." : model.log)
                        .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.ink)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }.frame(height: 150).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        eyebrow("LOCATION WORKSPACE")
                        Spacer()
                        StatusPill(text: model.sessionTitle, color: statusColor, background: statusBackground)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Set your location.").font(.system(size: 36, weight: .semibold))
                            .tracking(-1.5).foregroundStyle(Palette.ink)
                        Text("A new coordinate. The same iPhone.")
                            .font(.system(size: 15)).foregroundStyle(Palette.muted)
                    }.padding(.top, 6).padding(.bottom, 4)
                    destination
                    session
                    diagnostics
                }.frame(maxWidth: 760).padding(32).frame(maxWidth: .infinity)
            }.background(Palette.canvas)
        }.frame(minWidth: 940, minHeight: 740).preferredColorScheme(.dark)
    }
}
