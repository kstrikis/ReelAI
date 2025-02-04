import Foundation
import AVFoundation
import CoreImage

// MARK: - Extensions
private extension CMSampleBuffer {
    var cgImage: CGImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(self) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}

// MARK: - Camera Manager
final class CameraManager: NSObject, @unchecked Sendable {
    static let shared = CameraManager()
    
    private let captureSession = AVCaptureSession()
    private var deviceInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var sessionQueue = DispatchQueue(label: "video.preview.session")
    private var isFrontCameraActive = true
    
    private var addToPreviewStream: ((CGImage) -> Void)?
    
    lazy var previewStream: AsyncStream<CGImage> = {
        AsyncStream { continuation in
            addToPreviewStream = { cgImage in
                continuation.yield(cgImage)
            }
        }
    }()
    
    private var isAuthorized: Bool {
        get async {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            print("📸 Camera auth status: \(status.rawValue)")
            
            switch status {
            case .authorized:
                print("📸 Camera already authorized")
                return true
                
            case .notDetermined:
                print("📸 Requesting camera permission...")
                do {
                    let granted = try await withCheckedThrowingContinuation { continuation in
                        AVCaptureDevice.requestAccess(for: .video) { granted in
                            print("📸 Permission request completed: \(granted)")
                            continuation.resume(returning: granted)
                        }
                    }
                    print("📸 Permission request result: \(granted)")
                    return granted
                } catch {
                    print("❌ Permission request failed: \(error)")
                    return false
                }
                
            case .denied:
                print("❌ Camera permission denied")
                return false
                
            case .restricted:
                print("❌ Camera access restricted")
                return false
                
            @unknown default:
                print("❌ Unknown camera authorization status: \(status.rawValue)")
                return false
            }
        }
    }
    
    private override init() {
        super.init()
        print("📸 CameraManager singleton initialized")
    }
    
    func prepareAndStart() async {
        print("📸 Starting camera setup")
        await configureSession()
        await startSession()
    }
    
    func switchCamera() async {
        print("📸 Switching camera")
        isFrontCameraActive.toggle()
        await configureSession()
        await startSession()
    }
    
    private func getCurrentCamera() -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera]
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: isFrontCameraActive ? .front : .back
        )
        return discoverySession.devices.first
    }
    
    private func configureSession() async {
        AppLogger.methodEntry(AppLogger.ui)
        print("📸 Configuring camera session...")
        
        guard await isAuthorized else {
            print("❌ Camera not authorized")
            return
        }
        
        // Stop previous session if running
        stopSession()
        
        guard let camera = getCurrentCamera() else {
            print("❌ No camera device available")
            AppLogger.error(AppLogger.ui, CameraError.deviceNotAvailable)
            return
        }
        
        do {
            let deviceInput = try AVCaptureDeviceInput(device: camera)
            print("📸 Created device input")
            
            captureSession.beginConfiguration()
            defer {
                captureSession.commitConfiguration()
                print("📸 Committed session configuration")
            }
            
            // Remove previous inputs and outputs
            captureSession.inputs.forEach { captureSession.removeInput($0) }
            captureSession.outputs.forEach { captureSession.removeOutput($0) }
            
            let videoOutput = AVCaptureVideoDataOutput()
            videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            print("📸 Created video output")
            
            guard captureSession.canAddInput(deviceInput) else {
                print("❌ Cannot add input to session")
                AppLogger.error(AppLogger.ui, CameraError.setupFailed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to add device input to capture session"])))
                return
            }
            
            guard captureSession.canAddOutput(videoOutput) else {
                print("❌ Cannot add output to session")
                AppLogger.error(AppLogger.ui, CameraError.setupFailed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to add video output to capture session"])))
                return
            }
            
            captureSession.addInput(deviceInput)
            captureSession.addOutput(videoOutput)
            
            // Configure video connection
            if let connection = videoOutput.connection(with: .video) {
                if connection.isVideoMirroringSupported {
                    connection.isVideoMirrored = isFrontCameraActive
                }
                // Set rotation to portrait (0 degrees)
                connection.videoRotationAngle = 90
            }
            
            self.videoOutput = videoOutput
            print("📸 Successfully added input and output to session")
            
        } catch {
            print("❌ Failed to create device input: \(error.localizedDescription)")
            AppLogger.error(AppLogger.ui, CameraError.setupFailed(error))
        }
        
        AppLogger.methodExit(AppLogger.ui)
    }
    
    private func startSession() async {
        AppLogger.methodEntry(AppLogger.ui)
        print("📸 Starting camera session...")
        
        guard await isAuthorized else {
            print("❌ Cannot start session - not authorized")
            AppLogger.error(AppLogger.ui, CameraError.deviceNotAvailable)
            return
        }
        
        sessionQueue.async { [weak self] in
            print("📸 Starting capture session...")
            self?.captureSession.startRunning()
            print("📸 Capture session started")
        }
        
        AppLogger.methodExit(AppLogger.ui)
    }
    
    func stopSession() {
        AppLogger.methodEntry(AppLogger.ui)
        print("📸 Stopping camera session...")
        
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            print("📸 Camera session stopped")
        }
        
        AppLogger.methodExit(AppLogger.ui)
    }
    
    func reset() {
        AppLogger.methodEntry(AppLogger.ui)
        print("📸 Resetting camera manager")
        stopSession()
        AppLogger.methodExit(AppLogger.ui)
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        guard let currentFrame = sampleBuffer.cgImage else { return }
        addToPreviewStream?(currentFrame)
    }
} 