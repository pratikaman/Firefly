import Foundation
import IOKit

/// Reads the built-in ambient light sensor on Apple Silicon Macs.
///
/// The classic `AppleLMUController` IOKit path died with Intel. On Apple Silicon the
/// sensor shows up as an HID service (usage page 0xFF00, usage 4, product "als") driven
/// by `AppleSPUVD6286`. Two things are worth reading off it:
///
///   * `CurrentLux` on the driver — a real lux figure, when the driver bothers to fill it in.
///   * The raw ALS channels on the HID event — always live, but in sensor counts, not lux.
///
/// We prefer lux and fall back to a calibrated curve over the raw channels, because on
/// some machines (this one included) `CurrentLux` sits at 0 indoors and only wakes up
/// under real brightness.
final class AmbientLight {

    struct Reading {
        /// Best-effort illuminance in lux.
        var lux: Double
        /// Correlated colour temperature in Kelvin, 0 when unknown.
        var kelvin: Double
        /// True when `lux` came from raw sensor counts rather than the driver's own figure.
        var estimated: Bool
        /// The four raw ALS channels, surfaced so the UI can show what the sensor really sees.
        var raw: [Double]
    }

    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchFn = @convention(c) (AnyObject, CFDictionary) -> Void
    private typealias CopySvcsFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, Int32) -> Double

    private let copyEvent: CopyEventFn
    private let getFloat: GetFloatFn

    /// All three of these must be held for the lifetime of the object.
    ///
    /// The service clients are owned by the event system client, and the array owns the
    /// elements handed out by `CopyServices`. Letting either go while keeping only the
    /// service leaves a dangling pointer that `IOHIDServiceClientCopyEvent` will happily
    /// dereference — which reads fine from a terminal and crashes under LaunchServices.
    private let client: AnyObject
    private let services: NSArray
    private let service: AnyObject

    /// `kIOHIDEventTypeAmbientLightSensor`.
    private static let alsEventType: Int64 = 12
    private static let fieldBase = Int32(12 << 16)

    init?() {
        func sym(_ name: String) -> UnsafeMutableRawPointer? {
            dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
        }
        guard let pCreate = sym("IOHIDEventSystemClientCreate"),
              let pMatch = sym("IOHIDEventSystemClientSetMatching"),
              let pServices = sym("IOHIDEventSystemClientCopyServices"),
              let pEvent = sym("IOHIDServiceClientCopyEvent"),
              let pFloat = sym("IOHIDEventGetFloatValue") else { return nil }

        let create = unsafeBitCast(pCreate, to: CreateFn.self)
        let setMatching = unsafeBitCast(pMatch, to: SetMatchFn.self)
        let copyServices = unsafeBitCast(pServices, to: CopySvcsFn.self)
        self.copyEvent = unsafeBitCast(pEvent, to: CopyEventFn.self)
        self.getFloat = unsafeBitCast(pFloat, to: GetFloatFn.self)

        guard let clientRef = create(kCFAllocatorDefault) else { return nil }
        let client = clientRef.takeRetainedValue()
        setMatching(client, ["PrimaryUsagePage": 0xFF00, "PrimaryUsage": 4] as CFDictionary)

        guard let servicesRef = copyServices(client) else { return nil }
        let services = servicesRef.takeRetainedValue() as NSArray
        guard let first = services.firstObject else { return nil }

        self.client = client
        self.services = services
        self.service = first as AnyObject
    }

    func read() -> Reading? {
        guard let eventRef = copyEvent(service, Self.alsEventType, 0, 0) else { return nil }
        let event = eventRef.takeRetainedValue()

        let kelvin = getFloat(event, Self.fieldBase + 10)

        // The driver's own lux figure is authoritative whenever it is actually populated.
        let channels = (1...4).map { getFloat(event, Self.fieldBase + Int32($0)) }

        // The HID level is the finest-grained source; the driver's `CurrentLux` quantises
        // hard (it steps 641 -> 779 while the HID level moves 636, 646, 669...).
        let driverLux = max(getFloat(event, Self.fieldBase), Self.currentLux() ?? 0)

        // Both driver sources bottom out around 1 lux and stop resolving, but the raw
        // channels keep going all the way to zero — so darkness is measured raw.
        if driverLux >= Self.driverFloor {
            return Reading(lux: driverLux, kelvin: kelvin, estimated: false, raw: channels)
        }
        return Reading(lux: Self.lux(fromRaw: channels), kelvin: kelvin, estimated: true, raw: channels)
    }

    /// Below this the driver's own lux figures stop resolving and just report 0 or 1.
    private static let driverFloor: Double = 2

    /// Counts-to-lux factor, measured on this hardware.
    ///
    /// Swept with a phone torch from a covered sensor to ~870 lux, the ratio of driver
    /// lux to summed raw counts held at 0.0351-0.0382 across the whole range — linear
    /// enough that a single constant beats any fitted curve.
    private static let luxPerCount: Double = 0.0366

    /// Maps raw ALS counts onto the same lux scale the driver reports.
    ///
    /// Only the first three channels are summed; the fourth tracks them closely and
    /// leaving it out keeps this consistent with how the factor above was measured.
    private static func lux(fromRaw channels: [Double]) -> Double {
        let signal = channels.prefix(3).reduce(0, +)
        return max(0, signal * luxPerCount)
    }

    /// Reads `CurrentLux` straight off the ALS driver, when it is populated.
    private static func currentLux() -> Double? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSPUVD6286"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service, "CurrentLux" as CFString, kCFAllocatorDefault, 0
        )?.takeRetainedValue() as? NSNumber else { return nil }
        let lux = value.doubleValue
        return lux > 0 ? lux : nil
    }
}
