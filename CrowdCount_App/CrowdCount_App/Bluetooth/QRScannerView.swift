import SwiftUI
import AVFoundation

struct QRScannerView: View {
    @Binding var scannedDeviceId: String
    @Binding var scannedDeviceSecret: String
    @Binding var isScanning: Bool
    @Environment(\.presentationMode) var presentationMode
    
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var showInvalidQRAlert: Bool = false
    @State private var invalidQRMessage: String = ""
    
    var body: some View {
        ZStack {
            QRCodeScannerRepresentable(
                scannedDeviceId: $scannedDeviceId,
                scannedDeviceSecret: $scannedDeviceSecret,
                isScanning: $isScanning,
                showError: $showError,
                errorMessage: $errorMessage
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                Spacer()
                
                // Scanner Frame
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white, lineWidth: 3)
                    .frame(width: 250, height: 250)
                    .overlay(
                        VStack {
                            Spacer()
                            Spacer()
                            Text("Scan QR Code")
                                .foregroundColor(.white)
                                .font(.headline)
                                .padding()
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(10)
                                .offset(y: 80)
                        }
                    )
                
                Spacer()
            }
            
            if showError {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(10)
                        .padding(.bottom, 50)
                }
            }
        }
        .alert("Incorrect QR Code", isPresented: $showInvalidQRAlert) {
            Button("Try Again") { }
        } message: {
            Text(invalidQRMessage)
        }
        .onChange(of: errorMessage) { _, newValue in
            if showError && !newValue.isEmpty {
                showError = false
                invalidQRMessage = newValue
                showInvalidQRAlert = true
            }
        }
    }
    
    struct QRCodeScannerRepresentable: UIViewControllerRepresentable {
        @Binding var scannedDeviceId: String
        @Binding var scannedDeviceSecret: String
        @Binding var isScanning: Bool
        @Binding var showError: Bool
        @Binding var errorMessage: String
        
        func makeUIViewController(context: Context) -> QRScannerViewController {
            let controller = QRScannerViewController()
            controller.delegate = context.coordinator
            return controller
        }
        
        func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {
            // No updates needed
        }
        
        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        class Coordinator: NSObject, QRScannerViewControllerDelegate {
            var parent: QRCodeScannerRepresentable
            
            init(_ parent: QRCodeScannerRepresentable) {
                self.parent = parent
            }
            
            func didScanQRCode(deviceId: String, deviceSecret: String) {
                parent.scannedDeviceId = deviceId
                parent.scannedDeviceSecret = deviceSecret
                parent.isScanning = false
            }
            
            func didFailWithError(error: String) {
                parent.errorMessage = error
                parent.showError = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self.parent.showError = false
                }
            }
        }
    }
    
    protocol QRScannerViewControllerDelegate: AnyObject {
        func didScanQRCode(deviceId: String, deviceSecret: String)
        func didFailWithError(error: String)
    }
    
    class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        weak var delegate: QRScannerViewControllerDelegate?
        
        var captureSession: AVCaptureSession!
        var previewLayer: AVCaptureVideoPreviewLayer!
        
        override func viewDidLoad() {
            super.viewDidLoad()
            
            view.backgroundColor = UIColor.black
            captureSession = AVCaptureSession()
            
            guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
                delegate?.didFailWithError(error: "Camera not available")
                return
            }
            
            let videoInput: AVCaptureDeviceInput
            
            do {
                videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            } catch {
                delegate?.didFailWithError(error: "Camera access denied")
                return
            }
            
            if (captureSession.canAddInput(videoInput)) {
                captureSession.addInput(videoInput)
            } else {
                failed()
                return
            }
            
            let metadataOutput = AVCaptureMetadataOutput()
            
            if (captureSession.canAddOutput(metadataOutput)) {
                captureSession.addOutput(metadataOutput)
                
                metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = [.qr]
            } else {
                failed()
                return
            }
            
            previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.frame = view.layer.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession.startRunning()
            }
        }
        
        func failed() {
            delegate?.didFailWithError(error: "Scanning not supported")
            captureSession = nil
        }
        
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            
            if (captureSession?.isRunning == false) {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.captureSession.startRunning()
                }
            }
        }
        
        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            
            if (captureSession?.isRunning == true) {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.captureSession.stopRunning()
                }
            }
        }
        
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            captureSession.stopRunning()
            
            if let metadataObject = metadataObjects.first {
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
                guard let stringValue = readableObject.stringValue else { return }
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
                found(code: stringValue)
            }
        }
        
        func found(code: String) {
            // Parse QR code format: crowdcount://provision?id=CC-00001&secret=abc123
            guard let url = URL(string: code),
                  url.scheme == "crowdcount",
                  url.host == "provision" else {
                delegate?.didFailWithError(error: "This is not a CrowdCount QR code. Please scan the QR code on your CrowdCount device.")
                resumeAfterDelay()
                return
            }
            
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            guard let queryItems = components?.queryItems,
                  let deviceId = queryItems.first(where: { $0.name == "id" })?.value,
                  !deviceId.isEmpty,
                  let deviceSecret = queryItems.first(where: { $0.name == "secret" })?.value,
                  !deviceSecret.isEmpty else {
                delegate?.didFailWithError(error: "This QR code is missing device information. Please make sure you're scanning the correct QR code on your CrowdCount device.")
                resumeAfterDelay()
                return
            }
            
            delegate?.didScanQRCode(deviceId: deviceId, deviceSecret: deviceSecret)
        }
        
        private func resumeAfterDelay() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.captureSession.startRunning()
                }
            }
        }
        
        override var prefersStatusBarHidden: Bool {
            return true
        }
        
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            return .portrait
        }
    }
}
