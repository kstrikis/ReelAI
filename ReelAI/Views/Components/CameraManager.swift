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
    private let systemPreferredCamera = AVCaptureDevice.default(for: .video)
    private var sessionQueue = DispatchQueue(label: "video.preview.session")
    private var isConfigured = false
    
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
        guard !isConfigured else { return }
        isConfigured = true
        
        print("📸 Starting camera setup")
        await configureSession()
        await startSession()
    }
    
    private func configureSession() async {
        AppLogger.methodEntry(AppLogger.ui)
        print("📸 Configuring camera session...")
        
        guard await isAuthorized else {
            print("❌ Camera not authorized")
            return
        }
        
        guard let systemPreferredCamera else {
            print("❌ No camera device available")
            AppLogger.error(AppLogger.ui, CameraError.deviceNotAvailable)
            return
        }
        
        do {
            let deviceInput = try AVCaptureDeviceInput(device: systemPreferredCamera)
            print("📸 Created device input")
            
            captureSession.beginConfiguration()
            defer {
                captureSession.commitConfiguration()
                print("📸 Committed session configuration")
            }
            
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
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                      didOutput sampleBuffer: CMSampleBuffer,
                      from connection: AVCaptureConnection) {
        guard let currentFrame = sampleBuffer.cgImage else { return }
        addToPreviewStream?(currentFrame)
    }
} 