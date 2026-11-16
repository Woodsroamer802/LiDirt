import SwiftUI

/// Offline Job Site viewer: high-res snapshot with pinch-zoom, pan, and rotate.
struct OfflineJobSiteView: View {
    let projectName: String
    let image: UIImage
    let meta: JobSiteOfflineMeta?
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var rotation: Angle = .zero
    @State private var lastRotation: Angle = .zero

    var body: some View {
        NavigationStack {
            ZStack {
                LiDirtColors.gunmetal.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .rotationEffect(rotation)
                    .offset(offset)
                    .gesture(dragGesture)
                    .gesture(magnifyGesture)
                    .gesture(rotateGesture)
                    .padding(8)

                VStack {
                    Spacer()
                    Text(helpText)
                        .font(LiDirtTypography.caption)
                        .foregroundStyle(LiDirtColors.textSecondary)
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .background(LiDirtColors.gunmetalDeep.opacity(0.92))
                }
            }
            .navigationTitle("Offline Job Site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") { resetView() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var helpText: String {
        var parts = ["Pinch to zoom · drag to pan · twist to orient"]
        if let meta {
            parts.append("Saved \(meta.savedAt.formatted(date: .abbreviated, time: .shortened))")
            parts.append("\(meta.imageWidthPx)×\(meta.imageHeightPx)px")
        }
        parts.append(projectName)
        return parts.joined(separator: " · ")
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(lastScale * value.magnification, 0.5), 8)
            }
            .onEnded { _ in
                lastScale = scale
            }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                rotation = lastRotation + value.rotation
            }
            .onEnded { _ in
                lastRotation = rotation
            }
    }

    private func resetView() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
        rotation = .zero
        lastRotation = .zero
    }
}
