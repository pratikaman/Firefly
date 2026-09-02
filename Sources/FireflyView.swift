import SwiftUI

/// shadcn/ui design tokens (zinc), translated to SwiftUI.
///
/// The look is monochrome on purpose: borders and muted foregrounds carry the hierarchy
/// rather than fills and accent colours. Both palettes are defined so the popover follows
/// the system appearance instead of forcing dark.
struct Tokens {
    let background, foreground: Color
    let card, cardForeground: Color
    let muted, mutedForeground: Color
    let border, input: Color
    let primary, primaryForeground: Color
    let secondary, secondaryForeground: Color
    let accent, destructive: Color

    static func hex(_ v: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((v >> 16) & 0xFF) / 255,
            green: Double((v >> 8) & 0xFF) / 255,
            blue: Double(v & 0xFF) / 255,
            opacity: 1
        )
    }

    static let light = Tokens(
        background: hex(0xFFFFFF), foreground: hex(0x09090B),
        card: hex(0xFFFFFF), cardForeground: hex(0x09090B),
        muted: hex(0xF4F4F5), mutedForeground: hex(0x71717A),
        border: hex(0xE4E4E7), input: hex(0xE4E4E7),
        primary: hex(0x18181B), primaryForeground: hex(0xFAFAFA),
        secondary: hex(0xF4F4F5), secondaryForeground: hex(0x18181B),
        accent: hex(0xF4F4F5), destructive: hex(0xEF4444)
    )

    static let dark = Tokens(
        background: hex(0x09090B), foreground: hex(0xFAFAFA),
        card: hex(0x09090B), cardForeground: hex(0xFAFAFA),
        muted: hex(0x27272A), mutedForeground: hex(0xA1A1AA),
        border: hex(0x27272A), input: hex(0x27272A),
        primary: hex(0xFAFAFA), primaryForeground: hex(0x18181B),
        secondary: hex(0x27272A), secondaryForeground: hex(0xFAFAFA),
        accent: hex(0x27272A), destructive: hex(0x7F1D1D)
    )

    static func of(_ scheme: ColorScheme) -> Tokens { scheme == .dark ? dark : light }
}

// MARK: - Primitives

/// `rounded-lg border bg-card`
private struct Card<Content: View>: View {
    let t: Tokens
    var padding: CGFloat = 12
    /// Fill the available height, so two cards in a Grid row line up top and bottom.
    var stretch: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(
                maxWidth: .infinity,
                maxHeight: stretch ? .infinity : nil,
                alignment: .topLeading
            )
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.card))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }
}

/// `inline-flex rounded-md border px-2 py-0.5 text-xs font-semibold`
private struct Badge: View {
    enum Variant { case primary, secondary, outline, destructive }
    let text: String
    let variant: Variant
    let t: Tokens

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(stroke, lineWidth: 1))
            .foregroundStyle(label)
    }

    private var fill: Color {
        switch variant {
        case .primary: return t.primary
        case .secondary: return t.secondary
        case .outline: return .clear
        case .destructive: return t.destructive
        }
    }
    private var stroke: Color { variant == .outline ? t.border : .clear }
    private var label: Color {
        switch variant {
        case .primary: return t.primaryForeground
        case .secondary: return t.secondaryForeground
        case .outline: return t.foreground
        case .destructive: return .white
        }
    }
}

/// `h-2 w-full rounded-full bg-primary/20` with a `bg-primary` indicator.
private struct Progress: View {
    let value: Double
    let t: Tokens

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(t.primary.opacity(0.2))
                Capsule()
                    .fill(t.primary)
                    .frame(width: max(0, min(1, value)) * geo.size.width)
            }
        }
        .frame(height: 8)
    }
}

/// shadcn Switch: pill track, floating thumb. Built by hand because the AppKit switch
/// can't be restyled and reads as system-blue rather than monochrome.
private struct SwitchControl: View {
    @Binding var isOn: Bool
    let t: Tokens

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? t.primary : t.input)
            Circle()
                .fill(isOn ? t.primaryForeground : t.background)
                .padding(2)
        }
        .frame(width: 34, height: 19)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        }
    }
}

/// shadcn Slider: thin track, `bg-primary` range, ringed thumb.
private struct SliderControl: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    let t: Tokens

    private let thumb: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (value - range.lowerBound) / span : 0
            let clamped = max(0, min(1, fraction))

            ZStack(alignment: .leading) {
                Capsule().fill(t.secondary).frame(height: 6)
                Capsule().fill(t.primary).frame(width: clamped * width, height: 6)
                Circle()
                    .fill(t.background)
                    .overlay(Circle().strokeBorder(t.primary, lineWidth: 2))
                    .frame(width: thumb, height: thumb)
                    .offset(x: clamped * (width - thumb))
            }
            .frame(height: thumb)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let position = (drag.location.x - thumb / 2) / max(1, width - thumb)
                    value = range.lowerBound + max(0, min(1, position)) * span
                }
            )
        }
        .frame(height: thumb)
    }
}

/// `variant="outline" size="sm"`
private struct OutlineButton: View {
    let title: String
    let caption: String
    let t: Tokens
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title).font(.system(size: 11, weight: .medium))
                Text(caption).font(.system(size: 10).monospacedDigit()).foregroundStyle(t.mutedForeground)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? t.accent : t.background))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.border, lineWidth: 1))
            .foregroundStyle(t.foreground)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct GhostButton: View {
    let title: String
    let t: Tokens
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(hovering ? t.accent : .clear))
                .foregroundStyle(t.mutedForeground)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Screen

struct FireflyView: View {
    @ObservedObject var controller: FireflyController
    @Environment(\.colorScheme) private var scheme
    @State private var latitudeText = ""
    @State private var longitudeText = ""

    private var t: Tokens { Tokens.of(scheme) }

    private var timeFormatter: DateFormatter {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Rectangle().fill(t.border).frame(height: 1)

            if !controller.keyboardAvailable || !controller.sensorAvailable {
                unavailable
            } else {
                keyboardCard
                readings
                if needsManualLocation { manualLocation }
                controls
            }

            Rectangle().fill(t.border).frame(height: 1)
            footer
        }
        .padding(14)
        .frame(width: 340)
        .background(t.background)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Firefly")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(t.foreground)
                Text("Automatic keyboard backlight")
                    .font(.system(size: 11))
                    .foregroundStyle(t.mutedForeground)
            }
            Spacer()
            SwitchControl(
                isOn: Binding(
                    get: { controller.settings.enabled },
                    set: { controller.settings.enabled = $0 }
                ),
                t: t
            )
        }
    }

    private var unavailable: some View {
        Card(t: t) {
            VStack(alignment: .leading, spacing: 6) {
                Badge(text: "Unavailable", variant: .destructive, t: t)
                Text(controller.keyboardAvailable ? "No ambient light sensor found." : "No keyboard backlight found.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(t.foreground)
                Text("Firefly needs an Apple Silicon Mac with a backlit built-in keyboard.")
                    .font(.system(size: 11))
                    .foregroundStyle(t.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var keyboardCard: some View {
        Card(t: t) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Keyboard backlight")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(t.mutedForeground)
                    Spacer()
                    statusBadge
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(Int((controller.applied * 100).rounded()))%")
                        .font(.system(size: 26, weight: .bold).monospacedDigit())
                        .foregroundStyle(t.foreground)
                    Spacer()
                    if abs(controller.target - controller.applied) > 0.01 {
                        Text("target \(Int((controller.target * 100).rounded()))%")
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(t.mutedForeground)
                    }
                }

                Progress(value: controller.applied, t: t)

                Text(controller.reason)
                    .font(.system(size: 11))
                    .foregroundStyle(t.mutedForeground)

                if controller.overriddenUntil != nil {
                    OutlineButton(title: "Resume automatic", caption: "you changed it manually", t: t) {
                        controller.resumeNow()
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var statusBadge: some View {
        Group {
            if !controller.settings.enabled {
                Badge(text: "Paused", variant: .secondary, t: t)
            } else if controller.overriddenUntil != nil {
                Badge(text: "Manual", variant: .outline, t: t)
            } else {
                Badge(text: "Auto", variant: .primary, t: t)
            }
        }
    }

    /// A Grid rather than an HStack: cells in a row share a height, so the two cards
    /// line up even when one has more to say than the other.
    private var readings: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 0) {
            GridRow {
                sunCard
                roomCard
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sunCard: some View {
        Card(t: t, padding: 10, stretch: true) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: controller.sun?.phase.symbol ?? "questionmark")
                        .font(.system(size: 10))
                    Text("Sun").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(t.mutedForeground)

                Text(controller.sun?.phase.rawValue ?? "No location")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(t.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                if let sun = controller.sun {
                    Text("\(sun.elevation, specifier: "%.1f")° elevation")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(t.mutedForeground)
                    if let rise = sun.sunrise, let set = sun.sunset {
                        Text("↑ \(timeFormatter.string(from: rise))   ↓ \(timeFormatter.string(from: set))")
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(t.mutedForeground)
                    }
                }
            }
        }
    }

    private var roomCard: some View {
        Card(t: t, padding: 10, stretch: true) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "light.max").font(.system(size: 10))
                    Text("Room").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(t.mutedForeground)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(controller.lux < 10
                         ? String(format: "%.1f", controller.lux)
                         : "\(Int(controller.lux.rounded()))")
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(t.foreground)
                    Text(controller.luxIsEstimated ? "lux est." : "lux")
                        .font(.system(size: 10))
                        .foregroundStyle(t.mutedForeground)
                }

                if !controller.rawChannels.isEmpty {
                    Text("raw " + controller.rawChannels.map { String(Int($0)) }.joined(separator: " · "))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(t.mutedForeground)
                }
                if controller.kelvin > 0 {
                    Text("\(Int(controller.kelvin)) K")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(t.mutedForeground)
                }
            }
        }
    }

    /// CoreLocation is off or was refused, so the sun needs coordinates by hand.
    /// Without this the footer tells you to "set coordinates" with nowhere to set them.
    private var needsManualLocation: Bool {
        switch controller.locationStatus {
        case .denied, .unset: return true
        case .waiting, .located: return false
        }
    }

    private var manualLocation: some View {
        Card(t: t, padding: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Location")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(t.foreground)
                Text("Location access is unavailable. Enter coordinates so Firefly can place the sun.")
                    .font(.system(size: 10))
                    .foregroundStyle(t.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    coordinateField("Latitude", text: $latitudeText)
                    coordinateField("Longitude", text: $longitudeText)
                    Button(action: applyManualLocation) {
                        Text("Set")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.primary))
                            .foregroundStyle(t.primaryForeground)
                    }
                    .buttonStyle(.plain)
                    .disabled(Double(latitudeText) == nil || Double(longitudeText) == nil)
                    .opacity(Double(latitudeText) == nil || Double(longitudeText) == nil ? 0.5 : 1)
                }
            }
        }
        .onAppear {
            if latitudeText.isEmpty && controller.settings.manualLatitude != 0 {
                latitudeText = String(controller.settings.manualLatitude)
                longitudeText = String(controller.settings.manualLongitude)
            }
        }
    }

    private func coordinateField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(t.foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.background))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.border, lineWidth: 1))
    }

    private func applyManualLocation() {
        guard let lat = Double(latitudeText), let lon = Double(longitudeText),
              (-90...90).contains(lat), (-180...180).contains(lon) else { return }
        var updated = controller.settings
        updated.manualLatitude = lat
        updated.manualLongitude = lon
        updated.useManualLocation = true
        controller.settings = updated
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sliderRow(
                label: "Maximum brightness",
                value: "\(Int(controller.settings.maxBrightness * 100))%",
                binding: Binding(
                    get: { controller.settings.maxBrightness },
                    set: { controller.settings.maxBrightness = $0 }
                ),
                range: 0...1
            )

            sliderRow(
                label: "Sun glow",
                value: controller.settings.duskGlow < 0.005
                    ? "sensor only"
                    : "+\(Int(controller.settings.duskGlow * 100))% after dark",
                binding: Binding(
                    get: { controller.settings.duskGlow },
                    set: { controller.settings.duskGlow = $0 }
                ),
                range: 0...0.5,
                help: "How much a dark sky adds on top of the sensor reading."
            )

            VStack(alignment: .leading, spacing: 6) {
                Text("Calibrate")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(t.foreground)
                Text("Tap in the lighting you mean, to teach it your room.")
                    .font(.system(size: 10))
                    .foregroundStyle(t.mutedForeground)
                HStack(spacing: 8) {
                    OutlineButton(title: "This is dark",
                                  caption: "\(fmt(controller.settings.darkLux)) lux", t: t) {
                        controller.settings.darkLux = max(0.5, controller.lux)
                    }
                    OutlineButton(title: "This is bright",
                                  caption: "\(fmt(controller.settings.brightLux)) lux", t: t) {
                        controller.settings.brightLux = max(controller.settings.darkLux * 2, controller.lux)
                    }
                }
            }
        }
    }

    private func fmt(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : "\(Int(value.rounded()))"
    }

    private func sliderRow(
        label: String,
        value: String,
        binding: Binding<Double>,
        range: ClosedRange<Double>,
        help: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(t.foreground)
                Spacer()
                Text(value)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(t.mutedForeground)
            }
            SliderControl(value: binding, range: range, t: t)
            if let help {
                Text(help)
                    .font(.system(size: 10))
                    .foregroundStyle(t.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 5) {
            Image(systemName: "location").font(.system(size: 9))
            Text(locationLabel).font(.system(size: 10))
            Spacer()
            GhostButton(title: "Quit", t: t) { NSApplication.shared.terminate(nil) }
        }
        .foregroundStyle(t.mutedForeground)
    }

    private var locationLabel: String {
        switch controller.locationStatus {
        case .waiting: return "Locating…"
        case .located(let source): return source == "manual" ? "Manual location" : "Located"
        case .denied: return "Location denied — set coordinates"
        case .unset: return "No location set"
        }
    }
}
