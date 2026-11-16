import Foundation
import MapKit
import CoreLocation
import Combine

@MainActor
final class SiteMapViewModel: NSObject, ObservableObject {
    @Published var region: MKCoordinateRegion
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var showTopo = true
    @Published var showParcels = true
    @Published var parcels: [ParcelPolygon] = []
    @Published var statusMessage = "Locating…"
    @Published var trespassWarning: String?
    @Published var isLoadingParcels = false
    @Published var parcelError: String?

    var parcelSourceURL: String
    private let locationManager = CLLocationManager()
    private let parcelService = ParcelBoundaryService()
    private var loadTask: Task<Void, Never>?

    /// Warn when within this distance of a mapped boundary edge.
    private let warnDistanceMeters: Double = 40

    init(
        initialCoordinate: CLLocationCoordinate2D? = nil,
        parcelSourceURL: String = ""
    ) {
        self.parcelSourceURL = parcelSourceURL
        if let initialCoordinate {
            region = MKCoordinateRegion(
                center: initialCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
            userCoordinate = initialCoordinate
        } else {
            // Contiguous US default until GPS fixes.
            region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
                span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 30)
            )
        }
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func onAppear() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        statusMessage = "Seeking GPS for site awareness…"
        scheduleParcelLoad()
    }

    func onDisappear() {
        locationManager.stopUpdatingLocation()
        loadTask?.cancel()
    }

    func refreshParcels() {
        scheduleParcelLoad()
    }

    func regionDidChange(_ newRegion: MKCoordinateRegion) {
        region = newRegion
        scheduleParcelLoad()
    }

    private func scheduleParcelLoad() {
        loadTask?.cancel()
        guard showParcels else {
            parcels = []
            parcelError = nil
            trespassWarning = nil
            return
        }
        let url = parcelSourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            parcels = []
            parcelError = nil
            statusMessage = "Set a county parcel FeatureServer URL in Settings for boundary lines."
            updateTrespassWarning()
            return
        }

        isLoadingParcels = true
        parcelError = nil
        let regionSnapshot = region
        loadTask = Task {
            do {
                try await Task.sleep(nanoseconds: 350_000_000) // debounce pan
                if Task.isCancelled { return }
                let loaded = try await parcelService.fetchParcels(
                    sourceURLString: url,
                    region: regionSnapshot
                )
                if Task.isCancelled { return }
                parcels = loaded
                statusMessage = "Loaded \(loaded.count) boundary ring(s) — approximate."
                isLoadingParcels = false
                updateTrespassWarning()
            } catch {
                if Task.isCancelled { return }
                parcels = []
                parcelError = error.localizedDescription
                isLoadingParcels = false
                updateTrespassWarning()
            }
        }
    }

    private func updateTrespassWarning() {
        guard showParcels, let userCoordinate, !parcels.isEmpty else {
            trespassWarning = nil
            return
        }
        if let distance = parcelService.nearestBoundaryDistanceMeters(
            from: userCoordinate,
            polygons: parcels
        ), distance <= warnDistanceMeters {
            trespassWarning =
                "Near a mapped boundary (~\(Int(distance)) m). Verify access before crossing — not a legal property line."
        } else {
            trespassWarning = nil
        }
    }
}

extension SiteMapViewModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.startUpdatingLocation()
            case .denied, .restricted:
                statusMessage = "Location denied — map still works; enable GPS for live position."
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            let coord = location.coordinate
            let firstFix = userCoordinate == nil
            userCoordinate = coord
            if firstFix {
                region = MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
                scheduleParcelLoad()
            }
            statusMessage = String(
                format: "GPS %.5f, %.5f (±%.0f m)",
                coord.latitude,
                coord.longitude,
                max(location.horizontalAccuracy, 0)
            )
            updateTrespassWarning()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            statusMessage = "GPS error — pan the map manually."
        }
    }
}
