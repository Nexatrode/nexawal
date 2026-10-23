import SwiftUI
import AVFoundation
import NexaWalLogic

struct QRScannerView: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.classicUI) private var classicUI
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.delegate = context.coordinator
        controller.neonMode = classicUI
        return controller
    }

    func updateUIViewController(_ controller: QRScannerViewController, context: Context) {
        controller.neonMode = classicUI
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan, dismiss: dismiss) }

    class Coordinator: NSObject, QRScannerViewControllerDelegate {
        let onScan: (String) -> Void
        let dismiss: DismissAction

        init(onScan: @escaping (String) -> Void, dismiss: DismissAction) {
            self.onScan = onScan
            self.dismiss = dismiss
        }

        func didFindCode(_ code: String) {
            dismiss()
            onScan(code)
        }
    }
}

protocol QRScannerViewControllerDelegate: AnyObject {
    func didFindCode(_ code: String)
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    weak var delegate: QRScannerViewControllerDelegate?
    var neonMode = false {
        didSet { if isViewLoaded { updateAppearance() } }
    }

    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let cameraQueue = DispatchQueue(label: "com.nexawal.qr-camera")
    private let overlayView = UIView()
    private let fillLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()
    private let targetAccessibilityView = UIView()
    private let instructionLabel = UILabel()
    private let unavailableLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private var unavailableMessage: String?
    private var didScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureOverlay()
        checkCameraPermission()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        overlayView.frame = view.bounds
        var divisions: [CGRect] = []
        if #available(iOS 27.1, *) {
            // UIKit frames already include the reserved region's interaction margins.
            divisions = view.reservedRegions(kind: .division).map(\.frame)
        }
        let safeBounds = view.bounds.inset(by: view.safeAreaInsets)
        let proposal = QRScannerLayout.resolve(safeBounds: safeBounds, divisions: divisions)
        let labelHeight = instructionLabel.sizeThatFits(
            CGSize(width: max(1, proposal.instruction.width), height: .greatestFiniteMagnitude)
        ).height
        let layout = QRScannerLayout.resolve(safeBounds: safeBounds, divisions: divisions,
                                             instructionHeight: labelHeight)
        let path = UIBezierPath(rect: view.bounds)
        let scanPath = UIBezierPath(roundedRect: layout.scanArea, cornerRadius: 12)
        path.append(scanPath)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fillLayer.frame = overlayView.bounds
        fillLayer.path = path.cgPath
        borderLayer.frame = overlayView.bounds
        borderLayer.path = scanPath.cgPath
        CATransaction.commit()
        targetAccessibilityView.frame = layout.scanArea
        instructionLabel.frame = layout.instruction
        unavailableLabel.frame = layout.scanArea.insetBy(dx: 8, dy: 8)
        closeButton.frame = layout.close
        cancelButton.frame = layout.cancel
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let session = captureSession, !didScan {
            cameraQueue.async { session.startRunning() }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let session = captureSession { cameraQueue.async { session.stopRunning() } }
    }

    private func checkCameraPermission() {
#if targetEnvironment(simulator)
        // The exact production overlay remains visible for resize/accessibility QA.
        showCameraUnavailable(L10n.t("Camera not available on simulator"))
#else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.viewIfLoaded?.window != nil else { return }
                    if granted { self.setupCamera() }
                    else { self.showCameraUnavailable(L10n.t("Camera permission denied")) }
                }
            }
        case .denied, .restricted: showCameraUnavailable(L10n.t("Camera access denied"))
        @unknown default: showCameraUnavailable(L10n.t("Unknown camera permission status"))
        }
#endif
    }

    private func setupCamera() {
        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video) else {
            showCameraUnavailable(L10n.t("No camera found")); return
        }
        let input: AVCaptureDeviceInput
        do { input = try AVCaptureDeviceInput(device: device) }
        catch { showCameraUnavailable(L10n.format("Could not access camera: %@", error.localizedDescription)); return }
        guard session.canAddInput(input) else {
            showCameraUnavailable(L10n.t("Could not add camera input")); return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showCameraUnavailable(L10n.t("Could not add metadata output")); return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
        captureSession = session
        view.setNeedsLayout()
        cameraQueue.async { session.startRunning() }
    }

    private func configureOverlay() {
        view.addSubview(overlayView)
        fillLayer.fillRule = .evenOdd
        fillLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor
        overlayView.layer.addSublayer(fillLayer)
        borderLayer.fillColor = UIColor.clear.cgColor
        borderLayer.lineWidth = 3
        overlayView.layer.addSublayer(borderLayer)
        targetAccessibilityView.isUserInteractionEnabled = false
        targetAccessibilityView.isAccessibilityElement = true
        targetAccessibilityView.accessibilityTraits = .image
        targetAccessibilityView.accessibilityLabel = L10n.t("Camera preview for scanning Monero QR codes")
        targetAccessibilityView.accessibilityIdentifier = "scanner-target"
        overlayView.addSubview(targetAccessibilityView)
        for label in [instructionLabel, unavailableLabel] {
            label.numberOfLines = 0
            label.textAlignment = .center
            label.adjustsFontForContentSizeCategory = true
            overlayView.addSubview(label)
        }
        for button in [closeButton, cancelButton] {
            button.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
            button.accessibilityLabel = L10n.t("Cancel")
            button.clipsToBounds = true
            overlayView.addSubview(button)
        }
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.accessibilityIdentifier = "scanner-close"
        cancelButton.accessibilityIdentifier = "scanner-cancel"
        updateAppearance()
    }

    private func updateAppearance() {
        let green = UIColor(red: 0.224, green: 1, blue: 0.078, alpha: 1)
        let tint: UIColor = neonMode ? green : .white
        borderLayer.strokeColor = tint.cgColor
        instructionLabel.text = L10n.neon("Scan Monero QR code", classicUI: neonMode)
        instructionLabel.textColor = tint
        instructionLabel.font = neonMode
            ? UIFontMetrics(forTextStyle: .headline).scaledFont(for: .monospacedSystemFont(ofSize: 17, weight: .bold))
            : .preferredFont(forTextStyle: .headline)
        unavailableLabel.text = unavailableMessage
        unavailableLabel.textColor = tint
        unavailableLabel.font = .preferredFont(forTextStyle: .body)
        cancelButton.setTitle(L10n.neon("Cancel", classicUI: neonMode), for: .normal)
        cancelButton.titleLabel?.font = neonMode
            ? UIFontMetrics(forTextStyle: .headline).scaledFont(for: .monospacedSystemFont(ofSize: 17, weight: .semibold))
            : .preferredFont(forTextStyle: .headline)
        cancelButton.titleLabel?.adjustsFontForContentSizeCategory = true
        for button in [closeButton, cancelButton] {
            button.tintColor = tint
            button.setTitleColor(tint, for: .normal)
            button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
            button.layer.cornerRadius = 12
            button.layer.borderWidth = neonMode ? 1 : 0
            button.layer.borderColor = tint.cgColor
        }
        view.setNeedsLayout()
    }

    @objc private func cancelTapped() {
        if let session = captureSession { cameraQueue.async { session.stopRunning() } }
        dismiss(animated: true)
    }

    private func showCameraUnavailable(_ message: String) {
        unavailableMessage = message
        updateAppearance()
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !didScan, let object = objects.first as? AVMetadataMachineReadableCodeObject,
              let code = object.stringValue else { return }
        didScan = true
        if let session = captureSession { cameraQueue.async { session.stopRunning() } }
        delegate?.didFindCode(code)
    }
}
