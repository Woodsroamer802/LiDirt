import SwiftUI
import MapKit

/// Apple Maps “live” view — street/satellite + GPS. Contours live on Job Site map after a scan.
struct LiveMapView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selectedProjectId: UUID?

    private var annotatedProjects: [LiveMapPin] {
        environment.projectStore.projects.compactMap { project in
            guard let site = project.jobSite, site.isValid else { return nil }
            return LiveMapPin(
                id: project.id,
                name: project.name,
                coordinate: site.center,
                address: project.address
            )
        }
    }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(annotatedProjects) { pin in
                Annotation(pin.name, coordinate: pin.coordinate) {
                    Button {
                        selectedProjectId = pin.id
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(LiDirtColors.constructionYellow)
                            Text(pin.name)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(LiDirtColors.textPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(LiDirtColors.gunmetalElevated.opacity(0.92), in: Capsule())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .bottom) {
            liveMapFooter
        }
        .background(LiDirtColors.gunmetal.ignoresSafeArea())
        .navigationTitle("Live map")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: Binding(
            get: { selectedProjectId != nil },
            set: { if !$0 { selectedProjectId = nil } }
        )) {
            if let selectedProjectId {
                ProjectDetailView(projectId: selectedProjectId)
            }
        }
    }

    private var liveMapFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Live Apple Map")
                .font(LiDirtTypography.headline)
                .foregroundStyle(LiDirtColors.textPrimary)
            Text(
                annotatedProjects.isEmpty
                    ? "Your GPS position. After a scan, open a project’s Job Site map for the Contour surface."
                    : "Pins mark Job Site outlines. Open a project for the Contour map after a scan."
            )
            .font(LiDirtTypography.caption)
            .foregroundStyle(LiDirtColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(LiDirtColors.gunmetalElevated.opacity(0.95))
    }
}

private struct LiveMapPin: Identifiable {
    var id: UUID
    var name: String
    var coordinate: CLLocationCoordinate2D
    var address: String?
}
