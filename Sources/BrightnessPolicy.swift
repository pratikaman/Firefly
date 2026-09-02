import Foundation

/// Decides how bright the keyboard should be, from the sun and the room.
///
/// The sensor is the base, and dusk only ever *adds* glow on top of it:
///
///     target = (how dark the room is) + glow · (1 - how dark the room is)
///     glow   = 0.30 · (how dark it is outside)
///
/// In daylight that reduces to trusting the sensor alone, which is the right answer —
/// a dark room needs the same light to type in whether it's 2pm or 2am. After dark it
/// lifts the whole curve, so a lamplit desk in the evening keeps a little glow.
///
///   * bright afternoon, sunlit desk   -> 0.00  (backlight is pointless, turn it off)
///   * evening, but a bright desk lamp -> 0.17  (a touch of glow)
///   * night, dark room                -> 1.00  (full backlight)
///   * dark room at 2pm                -> 1.00  (blackout curtains still need light)
///
/// An earlier version averaged the two signals instead, which had the sun *subtracting*
/// from a dark daytime room and dimming keys you still couldn't see.
struct BrightnessPolicy {

    struct Inputs {
        var lux: Double
        var sunElevation: Double
        var phase: SunPosition.Phase
    }

    struct Decision {
        var target: Double
        /// 0 = pitch black room, 1 = as bright as we ever expect indoors.
        var ambientNormalized: Double
        var reason: String
    }

    var settings: Settings

    func decide(_ inputs: Inputs) -> Decision {
        let ambient = normalizedAmbient(lux: inputs.lux)
        let daylight = inputs.phase.daylight

        let roomNeed = 1 - ambient
        let glow = settings.duskGlow * (1 - daylight)

        // Screen blend rather than an average: glow fills the headroom the room leaves,
        // so it can lift a bright room off zero but never pull a dark one down. Full
        // daylight sets glow to 0, which collapses this to the sensor reading alone —
        // so no separate "bright daylight" clamp is needed.
        var target = roomNeed + glow * (1 - roomNeed)

        target = min(target, settings.maxBrightness)
        target = max(0, min(1, target))

        return Decision(target: target, ambientNormalized: ambient, reason: describe(inputs, ambient: ambient, target: target))
    }

    /// Maps lux onto 0...1 logarithmically, because perceived brightness is logarithmic
    /// and the useful indoor range spans three orders of magnitude.
    private func normalizedAmbient(lux: Double) -> Double {
        let dark = max(settings.darkLux, 0.1)
        let bright = max(settings.brightLux, dark * 2)
        let value = (log10(max(lux, 0.1)) - log10(dark)) / (log10(bright) - log10(dark))
        return max(0, min(1, value))
    }

    private func describe(_ inputs: Inputs, ambient: Double, target: Double) -> String {
        let room: String
        switch ambient {
        case ..<0.15: room = "dark room"
        case ..<0.45: room = "dim room"
        case ..<0.80: room = "lit room"
        default: room = "bright room"
        }
        if target <= 0.02 { return "\(inputs.phase.rawValue), \(room) — off" }
        return "\(inputs.phase.rawValue), \(room)"
    }
}

/// User-tunable knobs, persisted in UserDefaults.
struct Settings {
    var enabled: Bool = true
    /// Never drive the backlight above this, even in a pitch-black room at 3am.
    var maxBrightness: Double = 1.0
    /// How much glow a fully dark sky adds to a room that needs none of its own.
    /// This is the whole of the sun's influence; set it to 0 for sensor-only behaviour.
    var duskGlow: Double = 0.30
    /// Lux at or below which the room counts as fully dark.
    /// A lamp-lit room at night measures under 1 lux on this sensor, so the floor is low.
    var darkLux: Double = 2
    /// Lux at or above which the room counts as fully bright.
    var brightLux: Double = 300
    /// How long to stand down after you adjust the backlight yourself.
    var manualOverrideMinutes: Double = 20
    /// Manual coordinates, used when CoreLocation is unavailable or denied.
    var manualLatitude: Double = 0
    var manualLongitude: Double = 0
    var useManualLocation: Bool = false

    private enum Key {
        static let enabled = "enabled"
        static let maxBrightness = "maxBrightness"
        static let duskGlow = "duskGlow"
        static let darkLux = "darkLux"
        static let brightLux = "brightLux"
        static let overrideMinutes = "manualOverrideMinutes"
        static let latitude = "manualLatitude"
        static let longitude = "manualLongitude"
        static let useManual = "useManualLocation"
    }

    static func load() -> Settings {
        let defaults = UserDefaults.standard
        var settings = Settings()
        if defaults.object(forKey: Key.enabled) != nil { settings.enabled = defaults.bool(forKey: Key.enabled) }
        if defaults.object(forKey: Key.maxBrightness) != nil { settings.maxBrightness = defaults.double(forKey: Key.maxBrightness) }
        if defaults.object(forKey: Key.duskGlow) != nil { settings.duskGlow = defaults.double(forKey: Key.duskGlow) }
        if defaults.object(forKey: Key.darkLux) != nil { settings.darkLux = defaults.double(forKey: Key.darkLux) }
        if defaults.object(forKey: Key.brightLux) != nil { settings.brightLux = defaults.double(forKey: Key.brightLux) }
        if defaults.object(forKey: Key.overrideMinutes) != nil { settings.manualOverrideMinutes = defaults.double(forKey: Key.overrideMinutes) }
        if defaults.object(forKey: Key.latitude) != nil { settings.manualLatitude = defaults.double(forKey: Key.latitude) }
        if defaults.object(forKey: Key.longitude) != nil { settings.manualLongitude = defaults.double(forKey: Key.longitude) }
        if defaults.object(forKey: Key.useManual) != nil { settings.useManualLocation = defaults.bool(forKey: Key.useManual) }
        return settings
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(enabled, forKey: Key.enabled)
        defaults.set(maxBrightness, forKey: Key.maxBrightness)
        defaults.set(duskGlow, forKey: Key.duskGlow)
        defaults.set(darkLux, forKey: Key.darkLux)
        defaults.set(brightLux, forKey: Key.brightLux)
        defaults.set(manualOverrideMinutes, forKey: Key.overrideMinutes)
        defaults.set(manualLatitude, forKey: Key.latitude)
        defaults.set(manualLongitude, forKey: Key.longitude)
        defaults.set(useManualLocation, forKey: Key.useManual)
    }
}
