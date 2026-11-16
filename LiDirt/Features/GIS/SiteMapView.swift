import SwiftUI
import MapKit

struct SiteMapView: View {
    @StateObject private var viewModel: SiteMapViewModel
    @Environment(\.dismiss) private var dismiss

    init(
        initialCoordinate: CLLocationCoordinate2D? = nil,
        parcelSourceURL: String = ""
    ) {
        _viewModel = StateObject(
            wrappedValue: SiteMapViewModel(
                initialCoordinate: initialCoordinate,
                parcelSourceURL: parcelSourceURL
            )
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            SiteMapRepresentable(viewModel: viewModel)
                .ignoresSafeArea(edges: .bottom)

            VStack(alignment: .leading, spacing: 10) {
                header
                if let warning = viewModel.trespassWarning {
                    Text(warning)
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.gunmetalDeep)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LiDirtColors.constructionYellow, in: RoundedRectangle(cornerRadius: 10))
                }
                Spacer()
                footer
            }
            .padding(16)
        }
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("Site map")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.statusMessage)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textPrimary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 10) {
                toggleChip("USGS topo", isOn: $viewModel.showTopo)
                toggleChip("Parcels", isOn: $viewModel.showParcels)
                Button {
                    viewModel.refreshParcels()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(LiDirtColors.constructionYellow)
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("Refresh parcels")
            }

            if viewModel.isLoadingParcels {
                ProgressView()
                    .tint(LiDirtColors.constructionYellow)
            }
            if let parcelError = viewModel.parcelError {
                Text(parcelError)
                    .font(LiDirtTypography.caption)
                    .foregroundStyle(LiDirtColors.danger)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(GISDisclaimer.trespass)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textSecondary)
            Text(GISDisclaimer.notOnX)
                .font(LiDirtTypography.caption)
                .foregroundStyle(LiDirtColors.textMuted)
        }
        .padding(12)
        .background(LiDirtColors.gunmetalDeep.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
    }

    private func toggleChip(_ title: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
            if title == "Parcels" {
                viewModel.refreshParcels()
            }
        } label: {
            Text(title)
                .font(LiDirtTypography.caption)
                .foregroundStyle(isOn.wrappedValue ? LiDirtColors.gunmetalDeep : LiDirtColors.constructionYellow)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(
                        isOn.wrappedValue
                        ? LiDirtColors.constructionYellow
                        : LiDirtColors.gunmetalElevated
                    )
                )
                .overlay(
                    Capsule().stroke(LiDirtColors.constructionYellow, lineWidth: 1)
                )
        }
    }
}

struct SiteMapRepresentable: UIViewRepresentable {
    @ObservedObject var viewModel: SiteMapViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.isRotateEnabled = true
        map.setRegion(viewModel.region, animated: false)
        context.coordinator.mapView = map
        context.coordinator.applyOverlays()
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.applyOverlays()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var viewModel: SiteMapViewModel
        weak var mapView: MKMapView?
        private var topoOverlay: MKTileOverlay?
        private var lastParcelIDs: [String] = []

        init(viewModel: SiteMapViewModel) {
            self.viewModel = viewModel
        }

        func applyOverlays() {
            guard let mapView else { return }

            if viewModel.showTopo {
                if topoOverlay == nil {
                    let overlay = USGSTopoOverlay.makeOverlay()
                    topoOverlay = overlay
                    mapView.addOverlay(overlay, level: .aboveRoads)
                }
            } else if let topoOverlay {
                mapView.removeOverlay(topoOverlay)
                self.topoOverlay = nil
            }

            let ids = viewModel.parcels.map(\.id)
            if ids != lastParcelIDs || !viewModel.showParcels {
                for overlay in mapView.overlays where overlay is MKPolygon {
                    mapView.removeOverlay(overlay)
                }
                lastParcelIDs = viewModel.showParcels ? ids : []
                if viewModel.showParcels {
                    for parcel in viewModel.parcels {
                        var coords = parcel.coordinates
                        let polygon = MKPolygon(coordinates: &coords, count: coords.count)
                        polygon.title = parcel.label
                        mapView.addOverlay(polygon, level: .aboveLabels)
                    }
                }
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                // Match LiDirt construction yellow without bridging SwiftUI Color.
                let yellow = UIColor(red: 0.96, green: 0.78, blue: 0.12, alpha: 1)
                renderer.strokeColor = yellow
                renderer.fillColor = yellow.withAlphaComponent(0.12)
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            viewModel.regionDidChange(mapView.region)
        }
    }
}
