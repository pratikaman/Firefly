import Foundation
import Combine

/// The engine: samples the room, asks the policy what to do, and eases the backlight there.
///
/// Two timers on purpose. A slow one re-reads the sensor and recomputes the target, and a
/// fast one nudges the actual backlight toward that target a little at a time. Splitting
/// them is what makes the result feel like ambient behaviour instead of a light switch.
@MainActor
final class FireflyController: ObservableObject {

    @Published private(set) var lux: Double = 0
    @Published private(set) var rawChannels: [Double] = []
    @Published private(set) var luxIsEstimated = false
    @Published private(set) var kelvin: Double = 0
    @Published private(set) var sun: SunPosition.Result?
    @Published private(set) var target: Double = 0
    @Published private(set) var applied: Double = 0
    @Published private(set) var reason: String = "Starting up"
    @Published private(set) var overriddenUntil: Date?
    @Published private(set) var sensorAvailable = true
    @Published private(set) var keyboardAvailable = true
    @Published private(set) var locationStatus: LocationProvider.Status = .waiting

    @Published var settings: Settings {
        didSet {
            settings.save()
            location.update(settings: settings)
            if !settings.enabled { overriddenUntil = nil }
            tick()
        }
    }

    private let sensor = AmbientLight()
    private let keyboard = KeyboardBacklight()
    private let location: LocationProvider

    private var sampleTimer: Timer?
    private var rampTimer: Timer?

    /// What we last wrote, so we can tell our own changes apart from the user's.
    private var lastWritten: Double?

    private let sampleInterval: TimeInterval = 4
    private let rampInterval: TimeInterval = 0.2
    /// Largest backlight change per ramp step — about a 2 second fade end to end.
    private let rampStep: Double = 0.1
    /// A gap this big between what we wrote and what's set means a human turned the knob.
    /// Reads come back exactly as written, so this only has to clear one F5 step (~6%).
    private let overrideThreshold: Double = 0.03

    init() {
        let loaded = Settings.load()
        self.settings = loaded
        self.location = LocationProvider(settings: loaded)
        self.sensorAvailable = sensor != nil
        self.keyboardAvailable = keyboard != nil

        location.onUpdate = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.locationStatus = self.location.status
                self.tick()
            }
        }
        location.start()

        // macOS ships its own ambient keyboard dimming; two controllers on one backlight
        // just fight, so we stand it down while Firefly is running.
        keyboard?.setSystemAutoBrightness(false)

        applied = keyboard?.brightness ?? 0
        start()
    }

    func start() {
        sampleTimer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        rampTimer = Timer.scheduledTimer(withTimeInterval: rampInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.ramp() }
        }
        tick()
    }

    /// Re-read the world and recompute the target.
    func tick() {
        if let reading = sensor?.read() {
            lux = reading.lux
            kelvin = reading.kelvin
            luxIsEstimated = reading.estimated
            rawChannels = reading.raw
        }

        let coordinate = location.coordinate
        let sunResult = coordinate.map {
            SunPosition.calculate(at: Date(), latitude: $0.latitude, longitude: $0.longitude)
        }
        sun = sunResult
        locationStatus = location.status

        guard settings.enabled else {
            reason = "Paused"
            return
        }

        // With no location we still have the sensor, which is the stronger of the two
        // signals anyway — assume daylight-neutral rather than refusing to work.
        let phase = sunResult?.phase ?? .civilTwilight
        let decision = BrightnessPolicy(settings: settings).decide(
            .init(lux: lux, sunElevation: sunResult?.elevation ?? 0, phase: phase)
        )
        target = decision.target
        reason = decision.reason
    }

    /// Ease the real backlight one step toward the target.
    private func ramp() {
        guard let keyboard, settings.enabled else { return }

        // macOS idle-dims the backlight when you step away, and suppresses it while the
        // display sleeps. Both are worth keeping, so stand aside instead of fighting them
        // — and, just as importantly, don't mistake either for the user hitting F5. The
        // dim arrives in small steps, so it slips under the override threshold and would
        // otherwise turn into a tug of war.
        if keyboard.isDimmed || keyboard.isSuppressed {
            lastWritten = nil
            return
        }

        let current = Double(keyboard.brightness)
        applied = current

        // Did the user grab the F5/F6 keys since our last write?
        if let written = lastWritten, abs(current - written) > overrideThreshold {
            overriddenUntil = Date().addingTimeInterval(settings.manualOverrideMinutes * 60)
            reason = "Manual override — you set it to \(Int(current * 100))%"
            lastWritten = nil
            return
        }

        if let until = overriddenUntil {
            if Date() < until { return }
            overriddenUntil = nil
            tick()
        }

        let gap = target - current
        guard abs(gap) > 0.005 else { return }

        let next = current + max(-rampStep, min(rampStep, gap))
        keyboard.setBrightness(next)
        lastWritten = Double(keyboard.brightness)
        applied = next
    }

    /// Drop a manual override and hand control straight back to the policy.
    func resumeNow() {
        overriddenUntil = nil
        lastWritten = nil
        tick()
    }
}
