import SwiftUI
import AppKit
import MapKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}

/// Graphite dark theme. Hex values are shared with the contrast checks in NativeChecks.swift.
enum Palette {
    static let canvasHex: UInt32 = 0x0B0C10
    static let sidebarHex: UInt32 = 0x07080B
    static let surfaceHex: UInt32 = 0x14161C
    static let raisedHex: UInt32 = 0x1B1E26
    static let inputHex: UInt32 = 0x0E1015
    static let lineHex: UInt32 = 0x262A33
    static let controlLineHex: UInt32 = 0x6B7486
    static let inkHex: UInt32 = 0xF3F5F9
    static let mutedHex: UInt32 = 0xA2A9B7
    static let accentHex: UInt32 = 0x7CCBFF
    static let softHex: UInt32 = 0x10243A
    static let selectionHex: UInt32 = 0x172231
    static let buttonInkHex: UInt32 = 0x061320
    static let secondaryHex: UInt32 = 0x1B1E26
    static let disabledHex: UInt32 = 0x1D2028
    static let liveHex: UInt32 = 0x6FE3A5
    static let liveBackgroundHex: UInt32 = 0x0F2A1E
    static let warningHex: UInt32 = 0xFFC46B
    static let warningBackgroundHex: UInt32 = 0x2E2413
    static let dangerHex: UInt32 = 0xFF8FA3

    static let canvas = Color(hex: canvasHex)
    static let sidebar = Color(hex: sidebarHex)
    static let surface = Color(hex: surfaceHex)
    static let raised = Color(hex: raisedHex)
    static let input = Color(hex: inputHex)
    static let line = Color(hex: lineHex)
    static let controlLine = Color(hex: controlLineHex)
    static let ink = Color(hex: inkHex)
    static let muted = Color(hex: mutedHex)
    static let accent = Color(hex: accentHex)
    static let soft = Color(hex: softHex)
    static let selection = Color(hex: selectionHex)
    static let buttonInk = Color(hex: buttonInkHex)
    static let secondary = Color(hex: secondaryHex)
    static let disabled = Color(hex: disabledHex)
    static let live = Color(hex: liveHex)
    static let liveBackground = Color(hex: liveBackgroundHex)
    static let warning = Color(hex: warningHex)
    static let warningBackground = Color(hex: warningBackgroundHex)
    static let danger = Color(hex: dangerHex)
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
        CableMark().stroke(Palette.accent, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round, lineJoin: .round))
            .padding(size * 0.2).frame(width: size, height: size)
            .background(Palette.soft, in: RoundedRectangle(cornerRadius: size * 0.28))
            .accessibilityHidden(true)
    }
}

/// SwiftUI's @State is a compiler macro that the Command Line Tools cannot expand, so local view state
/// lives in small observable objects instead.
final class Flag: ObservableObject { @Published var on = false }

final class ViewState: ObservableObject {
    @Published var camera: MapCameraPosition = .camera(
        MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: 20, longitude: 0), distance: 28_000_000))
    @Published var pickedOnMap = ""
    @Published var saving = false
    @Published var placeName = ""
    @Published var showGuide = false
}

struct ActionStyle: ButtonStyle {
    var primary = true
    var destructive = false
    func makeBody(configuration: Configuration) -> some View {
        ActionBody(configuration: configuration, primary: primary, destructive: destructive)
    }

    private struct ActionBody: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        let destructive: Bool
        @Environment(\.isEnabled) private var enabled
        @StateObject private var hover = Flag()

        var body: some View {
            let fill: Color = enabled ? (primary ? (destructive ? Palette.warning : Palette.accent) : Palette.secondary)
                : Palette.disabled
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? (primary ? Palette.buttonInk : Palette.ink) : Palette.muted)
                .frame(maxWidth: .infinity).frame(height: 46)
                .background(fill, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(primary && enabled ? Color.clear : (enabled ? Palette.controlLine : Palette.line)))
                .brightness(enabled && hover.on && !configuration.isPressed ? 0.06 : 0)
                .opacity(configuration.isPressed ? 0.8 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .onHover { hover.on = $0 }
        }
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration)
    }
    private struct IconBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @StateObject private var hover = Flag()
        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(enabled ? Palette.ink : Palette.muted.opacity(0.6))
                .frame(width: 34, height: 34)
                .background(hover.on && enabled ? Palette.raised : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .opacity(configuration.isPressed ? 0.7 : 1)
                .contentShape(RoundedRectangle(cornerRadius: 9))
                .onHover { hover.on = $0 }
        }
    }
}

struct PulseDot: View {
    let color: Color
    let animating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var pulse = Flag()
    var body: some View {
        ZStack {
            if animating && !reduceMotion {
                Circle().fill(color.opacity(0.35)).frame(width: 14, height: 14)
                    .scaleEffect(pulse.on ? 1.4 : 0.6).opacity(pulse.on ? 0 : 1)
            }
            Circle().fill(color).frame(width: 7, height: 7)
        }.frame(width: 14, height: 14).accessibilityHidden(true)
            .onAppear { pulse.on = false; withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse.on = true } }
    }
}

struct StatusPill: View {
    let text: String
    var color = Palette.accent
    var background = Palette.soft
    var live = false
    var body: some View {
        HStack(spacing: 6) {
            PulseDot(color: color, animating: live)
            Text(text).font(.system(size: 12, weight: .semibold))
        }.foregroundStyle(color).padding(.leading, 8).padding(.trailing, 12).padding(.vertical, 7)
            .background(background, in: Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Status: \(text)")
    }
}

struct DestinationPin: View {
    var live: Bool
    var body: some View {
        ZStack {
            Circle().fill((live ? Palette.live : Palette.accent).opacity(0.25)).frame(width: 34, height: 34)
            Circle().fill(live ? Palette.live : Palette.accent).frame(width: 16, height: 16)
                .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
        }.accessibilityLabel("Destination pin")
    }
}

struct ContentView: View {
    @ObservedObject var model: LocationModel
    var showsMap = true
    @FocusState private var coordinateFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var view = ViewState()

    private var validInput: Bool { model.point != nil }
    private var invalidInput: Bool { !model.coordinates.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !validInput }
    private var attention: Bool { model.failed || model.stopping || model.updateIsStale }
    private var statusColor: Color {
        if attention { return Palette.warning }
        if model.isLive { return Palette.live }
        return model.hasDevice && model.ready ? Palette.accent : Palette.muted
    }
    private var statusBackground: Color {
        attention ? Palette.warningBackground : (model.isLive ? Palette.liveBackground : Palette.soft)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(Palette.muted)
    }

    private func card<Content: View>(padding: CGFloat = 22, @ViewBuilder _ content: () -> Content) -> some View {
        content().padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line))
    }

    // MARK: Sidebar

    private var deviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: model.hasDevice ? "iphone.gen3" : "iphone.slash")
                    .font(.system(size: 20, weight: .regular)).foregroundStyle(model.hasDevice ? Palette.accent : Palette.muted)
                    .frame(width: 38, height: 38).background(Palette.raised, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.hasDevice ? "iPhone" : "No iPhone").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text(model.hasDevice ? "USB connected" : (model.ready ? "Connect with USB" : "Preparing support…"))
                        .font(.system(size: 12)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Button(action: model.refreshDevices) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(IconButtonStyle()).disabled(model.busy || !model.ready)
                    .help("Refresh USB devices (⌘R)").accessibilityLabel("Refresh USB devices")
                    .keyboardShortcut("r", modifiers: .command)
            }
            if model.devices.count > 1 {
                Picker("USB iPhone", selection: $model.selected) {
                    Text("Select an iPhone").tag("")
                    ForEach(model.devices, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().pickerStyle(.menu).disabled(model.busy).accessibilityLabel("USB iPhone")
            } else if model.hasDevice {
                Text(model.selected).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                    .help(model.selected).textSelection(.enabled)
            } else if model.ready {
                Text("Use a data cable, unlock your iPhone, then refresh.")
                    .font(.system(size: 12)).lineSpacing(2).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
    }

    private func placeRow(icon: String, title: String, detail: String?, coordinates: String) -> some View {
        let selected = CoordinateInput.extract(model.coordinates) == coordinates
        return Button { model.use(coordinates) } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 16)
                    .foregroundStyle(selected ? Palette.accent : Palette.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(Palette.ink).lineLimit(1)
                    if let detail {
                        Text(detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 10).padding(.vertical, 7)
                .background(selected ? Palette.selection : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(.plain).disabled(model.busy)
            .help(coordinates).accessibilityLabel("\(title), \(coordinates)")
    }

    private var placesList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                eyebrow("SAVED PLACES").padding(.horizontal, 10).padding(.bottom, 4)
                if model.places.isEmpty {
                    Text("Save a destination with the star to reuse it in one click.")
                        .font(.system(size: 12)).lineSpacing(2).foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 10)
                }
                ForEach(model.places) { place in
                    placeRow(icon: "star.fill", title: place.name, detail: place.coordinates, coordinates: place.coordinates)
                        .contextMenu {
                            Button("Use destination") { model.use(place.coordinates) }
                            Button("Copy coordinates") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(place.coordinates, forType: .string)
                            }
                            Divider()
                            Button("Remove", role: .destructive) { model.removePlace(place) }
                        }
                }
                if !model.recents.isEmpty {
                    HStack {
                        eyebrow("RECENT")
                        Spacer()
                        Button("Clear", action: model.clearRecents).buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                            .accessibilityLabel("Clear recent destinations")
                    }.padding(.horizontal, 10).padding(.top, 18).padding(.bottom, 4)
                    ForEach(model.recents, id: \.self) { recent in
                        placeRow(icon: "clock", title: model.name(for: recent) ?? recent, detail: nil, coordinates: recent)
                    }
                }
            }.padding(.horizontal, 12)
        }.scrollIndicators(.never)
    }

    private func guideStep(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)").font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.accent).frame(width: 20, height: 20)
                .background(Palette.soft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                Text(detail).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var guide: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { view.showGuide.toggle() }
            } label: {
                HStack {
                    Label("Setup checklist", systemImage: "checklist").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(guideVisible ? 180 : 0))
                }.foregroundStyle(Palette.muted).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(guideVisible ? "Hide setup checklist" : "Show setup checklist")
            if guideVisible {
                guideStep(1, "Connect & trust", "Unlock your iPhone and trust this Mac.")
                guideStep(2, "Enable Developer Mode", "Settings → Privacy & Security.")
                guideStep(3, "Verify in Maps", "Check the blue dot on your iPhone.")
            }
        }.padding(14).background(Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
    }

    private var guideVisible: Bool { view.showGuide || !model.hasDevice }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                BrandMark(size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cable Location").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    Text("iPhone location over USB").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }.padding(.horizontal, 18).padding(.top, 40)
            deviceCard.padding(.horizontal, 14)
            placesList.frame(maxHeight: .infinity)
            guide.padding(.horizontal, 14).padding(.bottom, 16)
        }.frame(width: 268).frame(maxHeight: .infinity).background(Palette.sidebar)
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.line).frame(width: 1) }
    }

    // MARK: Map

    private func focus(on point: (lat: Double, lon: Double), animated: Bool) {
        let target = MapCameraPosition.region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon),
            latitudinalMeters: 6000, longitudinalMeters: 6000))
        if animated && !reduceMotion { withAnimation(.easeInOut(duration: 0.6)) { view.camera = target } }
        else { view.camera = target }
    }

    @ViewBuilder private var mapSurface: some View {
        if showsMap {
            MapReader { proxy in
                Map(position: $view.camera) {
                    if let point = model.point {
                        Annotation("Destination", coordinate: CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon)) {
                            DestinationPin(live: model.isLive)
                        }.annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .mapControls { MapZoomStepper(); MapCompass() }
                .onTapGesture(coordinateSpace: .local) { location in
                    guard !model.busy, let coordinate = proxy.convert(location, from: .local) else { return }
                    model.pick(lat: coordinate.latitude, lon: coordinate.longitude)
                    view.pickedOnMap = model.coordinates
                }
            }
        } else {
            // Offscreen preview renders cannot load map tiles; show a neutral grid instead.
            Canvas { context, size in
                let grid = Path { path in
                    stride(from: 0, through: size.width, by: 36).forEach { path.move(to: CGPoint(x: $0, y: 0)); path.addLine(to: CGPoint(x: $0, y: size.height)) }
                    stride(from: 0, through: size.height, by: 36).forEach { path.move(to: CGPoint(x: 0, y: $0)); path.addLine(to: CGPoint(x: size.width, y: $0)) }
                }
                context.stroke(grid, with: .color(Palette.line), lineWidth: 1)
            }.background(Palette.input)
                .overlay { if model.point != nil { DestinationPin(live: model.isLive) } }
        }
    }

    private var mapCard: some View {
        ZStack(alignment: .bottomLeading) {
            mapSurface
            HStack(spacing: 8) {
                Image(systemName: model.point == nil ? "hand.tap" : "mappin.and.ellipse").font(.system(size: 11, weight: .semibold))
                if let point = model.point {
                    Text(model.name(for: model.coordinates) ?? CoordinateInput.readable(point.lat, point.lon))
                } else {
                    Text(model.busy ? "Map is locked during a session" : "Click the map to drop a pin")
                }
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.ink)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule()).environment(\.colorScheme, .dark)
                .padding(14).allowsHitTesting(false)
        }.frame(height: 270).clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line))
            .accessibilityElement(children: .contain).accessibilityLabel("Destination map")
    }

    // MARK: Destination

    private var savePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save place").font(.system(size: 13, weight: .semibold))
            TextField("Name, e.g. Home", text: $view.placeName).textFieldStyle(.roundedBorder).frame(width: 220)
                .onSubmit(commitSave)
            HStack {
                Spacer()
                Button("Cancel") { view.saving = false }.keyboardShortcut(.cancelAction)
                Button("Save", action: commitSave).keyboardShortcut(.defaultAction)
            }
        }.padding(16)
    }

    private func commitSave() {
        if model.savePlace(named: view.placeName) { view.saving = false }
    }

    private var coordinateField: some View {
        HStack(spacing: 10) {
            Image(systemName: "location").font(.system(size: 16))
                .foregroundStyle(coordinateFocused ? Palette.accent : Palette.muted).accessibilityHidden(true)
            TextField("", text: $model.coordinates)
                .textFieldStyle(.plain).font(.system(size: 16, design: .monospaced))
                .foregroundStyle(Palette.ink).focused($coordinateFocused).disabled(model.busy)
                .onSubmit { model.start() }.accessibilityLabel("Destination latitude and longitude")
                .overlay(alignment: .leading) {
                    if model.coordinates.isEmpty {
                        Text("Latitude, Longitude or a map link").font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(Palette.muted).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .help("Decimal degrees (latitude first), N/S/E/W notation, or an Apple/Google Maps link.")
            if validInput {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.live)
                    .accessibilityLabel("Valid coordinates")
            }
            Button { model.pasteFromClipboard() } label: { Image(systemName: "doc.on.clipboard") }
                .buttonStyle(IconButtonStyle()).disabled(model.busy)
                .help("Paste coordinates or a map link (⇧⌘V)").accessibilityLabel("Paste coordinates")
                .keyboardShortcut("v", modifiers: [.command, .shift])
            Button {
                view.placeName = model.name(for: model.coordinates) ?? ""
                view.saving = true
            } label: {
                Image(systemName: model.name(for: model.coordinates) == nil ? "star" : "star.fill")
                    .foregroundStyle(model.name(for: model.coordinates) == nil ? Palette.ink : Palette.warning)
            }
            .buttonStyle(IconButtonStyle()).disabled(!validInput)
            .help("Save this place (⌘S)").accessibilityLabel("Save place")
            .keyboardShortcut("s", modifiers: .command)
            .popover(isPresented: $view.saving, arrowEdge: .bottom) { savePopover }
        }.padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
            .background(Palette.input, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(coordinateFocused ? Palette.accent : (invalidInput ? Palette.danger : Palette.controlLine),
                        lineWidth: coordinateFocused ? 2 : 1))
    }

    private var destination: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Destination").font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    if let point = model.point {
                        Text(CoordinateInput.readable(point.lat, point.lon))
                            .font(.system(size: 12, design: .monospaced)).foregroundStyle(Palette.muted).textSelection(.enabled)
                    }
                }
                coordinateField
                Text(invalidInput ? "Enter a valid latitude (−90…90) and longitude (−180…180), or paste a map link." :
                     "Latitude first. Use a minus sign for south or west, or paste a Google or Apple Maps link.")
                    .font(.system(size: 12)).foregroundStyle(invalidInput ? Palette.danger : Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    if model.holding {
                        Button(action: model.stop) {
                            Label(model.stopping ? "Restoring…" : "Stop & restore", systemImage: "stop.fill")
                        }.buttonStyle(ActionStyle(destructive: true)).disabled(model.stopping)
                            .keyboardShortcut(".", modifiers: .command).help("Stop and restore (⌘.)")
                    } else {
                        Button(action: model.start) {
                            Label("Start location", systemImage: "location.fill")
                        }.buttonStyle(ActionStyle()).disabled(!model.canStart)
                            .keyboardShortcut(.return, modifiers: .command).help("Start (⌘↩)")
                    }
                    Button(action: model.restore) {
                        Label("Restore real location", systemImage: "arrow.uturn.backward")
                    }.buttonStyle(ActionStyle(primary: false)).disabled(!model.canRestore)
                        .help("Request a return to the iPhone’s real location, then verify in Maps.")
                }.padding(.top, 2)
                if !model.ready && !model.busy {
                    Button("Retry iPhone setup", action: model.setup).buttonStyle(.link).tint(Palette.accent)
                }
            }
        }
    }

    // MARK: Session

    private func metric(_ name: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(name, systemImage: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
            Text(value).font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.ink).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusMessage: String {
        model.updateIsStale && !model.stopping && !model.failed ? "No recent update. Check the cable and unlock your iPhone." : model.status
    }

    private var session: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(model.holding ? "Current session" : (model.updates > 0 ? "Last session" : "Session"))
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    if model.busy { ProgressView().controlSize(.small) }
                }
                HStack(spacing: 10) {
                    metric("Duration", model.sessionElapsed, icon: "timer")
                    metric("Updates", "\(model.updates)", icon: "arrow.triangle.2.circlepath")
                    metric("Last update", model.holding ? model.lastUpdateText : "—", icon: "dot.radiowaves.left.and.right")
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: attention ? "exclamationmark.triangle.fill" :
                            (model.isLive ? "waveform.path" : "info.circle"))
                        .foregroundStyle(statusColor).frame(width: 18).padding(.top, 1).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusMessage).font(.system(size: 13)).foregroundStyle(Palette.ink).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        Text("Service activity only. Verify the location in iPhone Maps.")
                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                    }
                    Spacer(minLength: 0)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(attention ? Palette.warningBackground : Palette.input, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Keep the cable connected and the Mac awake during a session.", systemImage: "cable.connector")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted)
                Spacer(minLength: 8)
                if model.showDetails && !model.log.isEmpty {
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(model.log, forType: .string)
                    }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.accent)
                        .accessibilityLabel("Copy diagnostics")
                }
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { model.showDetails.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Text("Diagnostics")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                            .rotationEffect(.degrees(model.showDetails ? 180 : 0))
                    }.font(.system(size: 12, weight: .medium)).padding(.vertical, 6)
                }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                    .accessibilityLabel(model.showDetails ? "Hide diagnostics" : "Show diagnostics")
            }
            if model.showDetails {
                ScrollView {
                    Text(model.log.isEmpty ? "No diagnostic messages yet." : model.log)
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.ink)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }.frame(height: 150).background(Palette.input, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line))
            }
        }
    }

    private var subtitle: String {
        if model.isLive { return "Your iPhone is reporting the destination below." }
        if model.holding { return "Holding the destination on your iPhone." }
        if !model.ready { return "Preparing iPhone support on this Mac." }
        return model.hasDevice ? "Pick a spot on the map, paste coordinates, or choose a saved place." :
            "Connect your iPhone with a USB data cable to begin."
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Set location").font(.system(size: 26, weight: .semibold)).tracking(-0.6)
                                .foregroundStyle(Palette.ink)
                            Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        StatusPill(text: model.sessionTitle, color: statusColor, background: statusBackground, live: model.isLive)
                    }.padding(.top, 14)
                    mapCard
                    destination
                    session
                    diagnostics
                }.frame(maxWidth: 820).padding(.horizontal, 28).padding(.vertical, 22).frame(maxWidth: .infinity)
            }.background(Palette.canvas)
        }
        .frame(minWidth: 960, minHeight: 760).preferredColorScheme(.dark)
        .onAppear { if let point = model.point { focus(on: point, animated: false) } }
        .onChange(of: model.coordinates) { _, new in
            if !CoordinateInput.valid(new), new.count > 6, let normalized = CoordinateInput.extract(new) {
                model.coordinates = normalized  // Convert pasted map links and N/S/E/W notation in place.
                return
            }
            guard let point = model.point else { return }
            if new == view.pickedOnMap { return }  // Keep the user's zoom when they clicked the map.
            focus(on: point, animated: true)
        }
    }
}
