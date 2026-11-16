import UIKit
import MapKit

/// Photo-crop style Job Site editor: one-finger drag to move, pinch to scale, rotate to twist.
final class JobSiteCropEditorView: UIView {
    weak var mapView: MKMapView?
    var onBoundsChanged: ((JobSiteBounds) -> Void)?

    private var boundsModel: JobSiteBounds
    private let dimView = UIView()
    private let frameLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private let hintLabel = UILabel()

    private var panStartBounds: JobSiteBounds?
    private var pinchStartWidth: Double = 0
    private var pinchStartLength: Double = 0
    private var rotateStartDegrees: Double = 0

    init(bounds: JobSiteBounds) {
        self.boundsModel = bounds
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        backgroundColor = .clear

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        dimView.isUserInteractionEnabled = false
        addSubview(dimView)

        frameLayer.fillColor = UIColor.clear.cgColor
        frameLayer.strokeColor = UIColor(red: 0.96, green: 0.78, blue: 0.12, alpha: 1).cgColor
        frameLayer.lineWidth = 2.5
        frameLayer.lineDashPattern = [10, 6]
        layer.addSublayer(frameLayer)

        handleLayer.fillColor = UIColor(red: 0.96, green: 0.78, blue: 0.12, alpha: 1).cgColor
        layer.addSublayer(handleLayer)

        hintLabel.text = "Drag to move · Pinch to resize · Twist to rotate"
        hintLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        hintLabel.textColor = UIColor(red: 0.96, green: 0.78, blue: 0.12, alpha: 1)
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 2
        hintLabel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        hintLabel.layer.cornerRadius = 8
        hintLabel.clipsToBounds = true
        addSubview(hintLabel)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinch)

        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate(_:)))
        addGestureRecognizer(rotate)

        pinch.delegate = self
        rotate.delegate = self
        pan.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(bounds: JobSiteBounds) {
        boundsModel = bounds
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        dimView.frame = bounds
        hintLabel.frame = CGRect(
            x: 16,
            y: bounds.height - safeAreaInsets.bottom - 52,
            width: bounds.width - 32,
            height: 36
        )
        redrawCrop()
    }

    private func redrawCrop() {
        guard let mapView else { return }
        let corners = boundsModel.cornerCoordinates
        guard corners.count == 4 else { return }
        let points = corners.map { mapView.convert($0, toPointTo: self) }
        let path = UIBezierPath()
        path.move(to: points[0])
        for p in points.dropFirst() { path.addLine(to: p) }
        path.close()

        // Dim outside crop
        let dimPath = UIBezierPath(rect: bounds)
        dimPath.append(path)
        dimPath.usesEvenOddFillRule = true
        let mask = CAShapeLayer()
        mask.fillRule = .evenOdd
        mask.path = dimPath.cgPath
        dimView.layer.mask = mask

        frameLayer.path = path.cgPath

        let handlePath = UIBezierPath()
        for p in points {
            handlePath.addArc(withCenter: p, radius: 6, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        }
        // Center handle
        let centerPt = mapView.convert(boundsModel.center, toPointTo: self)
        handlePath.addArc(withCenter: centerPt, radius: 5, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        handleLayer.path = handlePath.cgPath
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let mapView else { return }
        switch gesture.state {
        case .began:
            panStartBounds = boundsModel
        case .changed:
            guard let start = panStartBounds else { return }
            let translation = gesture.translation(in: self)
            let startCenter = mapView.convert(start.center, toPointTo: self)
            let newCenterPoint = CGPoint(x: startCenter.x + translation.x, y: startCenter.y + translation.y)
            let newCenter = mapView.convert(newCenterPoint, toCoordinateFrom: self)
            apply(start.recentered(to: newCenter))
        case .ended, .cancelled:
            panStartBounds = nil
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            pinchStartWidth = boundsModel.widthFeet
            pinchStartLength = boundsModel.lengthFeet
        case .changed:
            let scale = Double(gesture.scale)
            let width = JobSiteDefaults.clampSideFeet(pinchStartWidth * scale)
            let length = JobSiteDefaults.clampSideFeet(pinchStartLength * scale)
            apply(boundsModel.resizedToFeet(widthFeet: width, lengthFeet: length))
        default:
            break
        }
    }

    @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            rotateStartDegrees = boundsModel.rotationDegrees
        case .changed:
            // UIKit rotation is radians; positive is counterclockwise — convert to clockwise degrees from north.
            let deltaDegrees = -Double(gesture.rotation) * 180 / .pi
            apply(boundsModel.withRotationDegrees(rotateStartDegrees + deltaDegrees))
        default:
            break
        }
    }

    private func apply(_ bounds: JobSiteBounds) {
        boundsModel = bounds
        redrawCrop()
        onBoundsChanged?(bounds)
    }
}

extension JobSiteCropEditorView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
