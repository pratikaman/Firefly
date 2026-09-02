import Foundation

/// Where the sun is, using the NOAA solar position algorithm.
///
/// This is pure arithmetic — no network, no almanac table. Given a date and a
/// coordinate it returns the sun's elevation above the horizon, which is a far better
/// signal than clock time alone: 7pm is broad daylight in June and long dark in December.
enum SunPosition {

    /// How light it is outside, independent of what the room's lamps are doing.
    enum Phase: String {
        case day = "Day"
        case goldenHour = "Golden hour"
        case civilTwilight = "Civil twilight"
        case nauticalTwilight = "Nautical twilight"
        case astronomicalTwilight = "Astro twilight"
        case night = "Night"

        /// 0 = pitch dark outside, 1 = full daylight.
        var daylight: Double {
            switch self {
            case .day: return 1.0
            case .goldenHour: return 0.75
            case .civilTwilight: return 0.45
            case .nauticalTwilight: return 0.2
            case .astronomicalTwilight: return 0.07
            case .night: return 0.0
            }
        }

        var symbol: String {
            switch self {
            case .day: return "sun.max.fill"
            case .goldenHour: return "sun.horizon.fill"
            case .civilTwilight: return "sunset.fill"
            case .nauticalTwilight, .astronomicalTwilight: return "moon.haze.fill"
            case .night: return "moon.stars.fill"
            }
        }
    }

    struct Result {
        /// Sun elevation in degrees; negative means below the horizon.
        var elevation: Double
        var phase: Phase
        var sunrise: Date?
        var sunset: Date?
    }

    static func calculate(at date: Date, latitude: Double, longitude: Double) -> Result {
        let elevation = solarElevation(date: date, latitude: latitude, longitude: longitude)
        return Result(
            elevation: elevation,
            phase: phase(forElevation: elevation),
            sunrise: solarEvent(date: date, latitude: latitude, longitude: longitude, sunrise: true),
            sunset: solarEvent(date: date, latitude: latitude, longitude: longitude, sunrise: false)
        )
    }

    static func phase(forElevation elevation: Double) -> Phase {
        switch elevation {
        case 6...: return .day
        case 0..<6: return .goldenHour
        case -6..<0: return .civilTwilight
        case -12 ..< -6: return .nauticalTwilight
        case -18 ..< -12: return .astronomicalTwilight
        default: return .night
        }
    }

    // MARK: - NOAA algorithm

    private static func julianDay(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }

    /// Solar declination and the equation of time, both needed for elevation and rise/set.
    private static func solarTerms(julianCentury t: Double) -> (declination: Double, equationOfTime: Double) {
        let meanLongitude = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)

        let center = sin(rad(meanAnomaly)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(rad(2 * meanAnomaly)) * (0.019993 - 0.000101 * t)
            + sin(rad(3 * meanAnomaly)) * 0.000289

        let trueLongitude = meanLongitude + center
        let omega = 125.04 - 1934.136 * t
        let apparentLongitude = trueLongitude - 0.00569 - 0.00478 * sin(rad(omega))

        let meanObliquity = 23 + (26 + ((21.448 - t * (46.815 + t * (0.00059 - t * 0.001813)))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(rad(omega))

        let declination = deg(asin(sin(rad(obliquity)) * sin(rad(apparentLongitude))))

        let y = pow(tan(rad(obliquity / 2)), 2)
        let equationOfTime = 4 * deg(
            y * sin(2 * rad(meanLongitude))
            - 2 * eccentricity * sin(rad(meanAnomaly))
            + 4 * eccentricity * y * sin(rad(meanAnomaly)) * cos(2 * rad(meanLongitude))
            - 0.5 * y * y * sin(4 * rad(meanLongitude))
            - 1.25 * eccentricity * eccentricity * sin(2 * rad(meanAnomaly))
        )
        return (declination, equationOfTime)
    }

    private static func solarElevation(date: Date, latitude: Double, longitude: Double) -> Double {
        let jd = julianDay(date)
        let t = (jd - 2451545.0) / 36525.0
        let (declination, equationOfTime) = solarTerms(julianCentury: t)

        // Minutes past UTC midnight.
        let minutesUTC = (jd - floor(jd - 0.5) - 0.5) * 1440.0
        let trueSolarTime = (minutesUTC + equationOfTime + 4 * longitude)
            .truncatingRemainder(dividingBy: 1440)
        var hourAngle = trueSolarTime / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }

        let zenith = acos(
            sin(rad(latitude)) * sin(rad(declination))
            + cos(rad(latitude)) * cos(rad(declination)) * cos(rad(hourAngle))
        )
        return 90 - deg(zenith)
    }

    /// Sunrise or sunset for the calendar day containing `date`, at the standard -0.833° horizon.
    private static func solarEvent(date: Date, latitude: Double, longitude: Double, sunrise: Bool) -> Date? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let jd = julianDay(startOfDay)
        let t = (jd - 2451545.0) / 36525.0
        let (declination, equationOfTime) = solarTerms(julianCentury: t)

        let cosHourAngle = cos(rad(90.833)) / (cos(rad(latitude)) * cos(rad(declination)))
            - tan(rad(latitude)) * tan(rad(declination))
        // Polar day or polar night: the sun never crosses the horizon here today.
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }

        let hourAngle = deg(acos(cosHourAngle)) * (sunrise ? 1 : -1)
        let minutesUTC = 720 - 4 * (longitude + hourAngle) - equationOfTime

        // `minutesUTC` counts from UTC midnight, but `startOfDay` is *local* midnight —
        // adding the zone offset converts one to the other. Getting this sign wrong costs
        // you twice the offset, which is a very convincing 11 hours in IST.
        let localMidnight = calendar.startOfDay(for: date)
        let offset = TimeInterval(TimeZone.current.secondsFromGMT(for: date))
        return localMidnight.addingTimeInterval(offset + minutesUTC * 60)
    }
}
