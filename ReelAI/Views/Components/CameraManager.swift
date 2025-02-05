import AVFoundation
import CoreImage
import Foundation

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
    private var movieOutput: AVCaptureMovieFileOutput?
    private var sessionQueue = DispatchQueue(label: "video.preview.session")
    private var isFrontCameraActive = true
    private var isRecording = false
    private var currentRecordingURL: URL?

    private var addToPreviewStream: ((CGImage) -> Void)?

    lazy var previewStream: AsyncStream<CGImage> = AsyncStream { continuation in
        addToPreviewStream = { cgImage in
            continuation.yield(cgImage)
        }
    }

    // MARK: - Recording Control

    func startRecording() async throws -> URL {
        AppLogger.methodEntry(AppLogger.ui)

        guard !isRecording else {
            throw CameraError.recordingFailed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Already recording"]))
        }

        // Create temporary URL for recording
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "\(UUID().uuidString).mp4"
        let outputURL = tempDir.appendingPathComponent(fileName)

        // Remove any existing file
        try? FileManager.default.removeItem(at: outputURL)

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.recordingFailed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "CameraManager deallocated"])))
                    return
                }

                movieOutput?.startRecording(to: outputURL, recordingDelegate: self)
                currentRecordingURL = outputURL
                isRecording = true

                continuation.resume(returning: outputURL)
            }
        }
    }

    func stopRecording() async throws -> URL {
        AppLogger.methodEntry(AppLogger.ui)

        guard isRecording, let outputURL = currentRecordingURL else {
            throw CameraError.recordingFailed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not recording"]))
        }

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraError.recordingFailed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "CameraManager deallocated"])))
                    return
                }

                movieOutput?.stopRecording()
                // URL will be returned in fileOutput(_:didFinishRecordingTo:from:error:)
                continuation.resume(returning: outputURL)
            }
        }
    }

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

    override private init() {
        super.init()
        print("📸 CameraManager singleton initialized")
    }

    func prepareAndStart() async {
        print("📸 Starting camera setup")
        await configureSession()
        await startSession()
    }

    func switchCamera() async {
        AppLogger.methodEntry(AppLogger.ui)
        print("📸 Switching camera")

        do {
            // Stop the current session first
            stopSession()

            // Toggle camera position
            isFrontCameraActive.toggle()
            print("📸 Switching to \(isFrontCameraActive ? "front" : "back") camera")

            // Wait a brief moment to ensure cleanup
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

            // Configure and start new session
            await configureSession()
            await startSession()

            print("📸 Camera switch completed successfully")
        } catch {
            print("❌ Camera switch failed: \(error.localizedDescription)")
            AppLogger.error(AppLogger.ui, CameraError.setupFailed(error))

            // Try to recover by reverting to previous camera
            isFrontCameraActive.toggle()
            await configureSession()
            await startSession()
        }

        AppLogger.methodExit(AppLogger.ui)
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

        do {
            // Stop previous session if running
            stopSession()

            // Wait briefly for cleanup
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

            guard let camera = getCurrentCamera() else {
                print("❌ No camera device available")
                AppLogger.error(AppLogger.ui, CameraError.deviceNotAvailable)
                return
            }

            let deviceInput = try createDeviceInput(from: camera)
            let videoOutput = createVideoOutput()

            try configureSessionComponents(deviceInput: deviceInput, videoOutput: videoOutput)
            configureVideoConnection(for: videoOutput)

            self.deviceInput = deviceInput
            self.videoOutput = videoOutput
            print("📸 Successfully configured session with new camera")
        } catch {
            print("❌ Failed to configure session: \(error.localizedDescription)")
            AppLogger.error(AppLogger.ui, CameraError.setupFailed(error))
        }

        AppLogger.methodExit(AppLogger.ui)
    }

    private func createDeviceInput(from camera: AVCaptureDevice) throws -> AVCaptureDeviceInput {
        let deviceInput = try AVCaptureDeviceInput(device: camera)
        print("📸 Created device input")
        return deviceInput
    }

    private func createVideoOutput() -> AVCaptureVideoDataOutput {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        print("📸 Created video output")
        return videoOutput
    }

    private func configureSessionComponents(
        deviceInput: AVCaptureDeviceInput,
        videoOutput: AVCaptureVideoDataOutput
    ) throws {
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
            print("📸 Committed session configuration")
        }

        // Remove previous inputs and outputs
        captureSession.inputs.forEach { captureSession.removeInput($0) }
        captureSession.outputs.forEach { captureSession.removeOutput($0) }

        let setupError = NSError(
            domain: "",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to add device input to capture session"]
        )

        guard captureSession.canAddInput(deviceInput) else {
            print("❌ Cannot add input to session")
            throw CameraError.setupFailed(setupError)
        }

        guard captureSession.canAddOutput(videoOutput) else {
            print("❌ Cannot add output to session")
            throw CameraError.setupFailed(setupError)
        }

        // Configure movie output
        let movieOutput = AVCaptureMovieFileOutput()
        guard captureSession.canAddOutput(movieOutput) else {
            print("❌ Cannot add movie output to session")
            throw CameraError.setupFailed(setupError)
        }

        captureSession.addInput(deviceInput)
        captureSession.addOutput(videoOutput)
        captureSession.addOutput(movieOutput)
        self.movieOutput = movieOutput
    }

    private func configureVideoConnection(for videoOutput: AVCaptureVideoDataOutput) {
        guard let connection = videoOutput.connection(with: .video) else { return }

        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = isFrontCameraActive
        }
        // Set rotation to portrait (90 degrees)
        connection.videoRotationAngle = 90
    }

    private func startSession() async {
        AppLogger.methodEntry(AppLogger.ui)
        print("📸 Starting camera session...")

        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                if !captureSession.isRunning {
                    captureSession.startRunning()
                    print("📸 Camera session started")
                }

                continuation.resume()
            }
        }
    }

    func stopSession() {
        AppLogger.methodEntry(AppLogger.ui)
        print("📸 Stopping camera session...")

        sessionQueue.async { [weak self] in
            guard let self else { return }

            if captureSession.isRunning {
                captureSession.stopRunning()
                print("📸 Camera session stopped")
            }

            // Clear existing inputs and outputs
            captureSession.beginConfiguration()
            captureSession.inputs.forEach { self.captureSession.removeInput($0) }
            captureSession.outputs.forEach { self.captureSession.removeOutput($0) }
            captureSession.commitConfiguration()

            // Clear references
            deviceInput = nil
            videoOutput = nil
            movieOutput = nil
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
    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        guard let currentFrame = sampleBuffer.cgImage else { return }
        addToPreviewStream?(currentFrame)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from _: [AVCaptureConnection], error: Error?) {
        AppLogger.methodEntry(AppLogger.ui)

        isRecording = false
        currentRecordingURL = nil

        if let error {
            AppLogger.error(AppLogger.ui, error)
        } else {
            AppLogger.debug("Recording finished successfully at: \(outputFileURL.path)")
        }

        AppLogger.methodExit(AppLogger.ui)
    }

    func fileOutput(_: AVCaptureFileOutput, didStartRecordingTo _: URL, from _: [AVCaptureConnection]) {
        AppLogger.methodEntry(AppLogger.ui)
        AppLogger.debug("Started recording")
        AppLogger.methodExit(AppLogger.ui)
    }
}
