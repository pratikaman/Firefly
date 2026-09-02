import Foundation
import CoreLocation

/// Supplies the coordinate the sun calculation needs.
///
/// Asks CoreLocation once and caches the answer; if permission is denied or the system
/// never answers, falls back to whatever coordinate the user typed into settings. The
/// sun maths needs roughly city-level accuracy, so a stale fix is perfectly fine.
final class LocationProvider: NSObject, CLLocationManagerDelegate {

    enum Status: Equatable {
        case waiting
        case located(source: String)
        case denied
        case unset
    }

    private let manager = CLLocationManager()
    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var status: Status = .waiting
    var onUpdate: (() -> Void)?

    private var settings: Settings

    init(settings: Settings) {
        self.settings = settings
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func update(settings: Settings) {
        self.settings = settings
        refresh()
    }

    func start() {
        if settings.useManualLocation {
            applyManual()
            return
        }
        guard CLLocationManager.locationServicesEnabled() else {
            applyManualOrDenied()
            return
        }
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    private func refresh() {
        if settings.useManualLocation {
            applyManual()
        } else {
            manager.startUpdatingLocation()
        }
    }

    private func applyManual() {
        guard settings.manualLatitude != 0 || settings.manualLongitude != 0 else {
            status = .unset
            onUpdate?()
            return
        }
        coordinate = CLLocationCoordinate2D(latitude: settings.manualLatitude, longitude: settings.manualLongitude)
        status = .located(source: "manual")
        onUpdate?()
    }

    private func applyManualOrDenied() {
        if settings.manualLatitude != 0 || settings.manualLongitude != 0 {
            applyManual()
        } else {
            status = .denied
            onUpdate?()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        coordinate = location.coordinate
        status = .located(source: "device")
        // One fix is plenty — the sun doesn't care about the last few kilometres.
        manager.stopUpdatingLocation()
        onUpdate?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        applyManualOrDenied()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            applyManualOrDenied()
        default:
            break
        }
    }
}
