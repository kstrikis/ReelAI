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
        Log.p(Log.camera, Log.start, "Starting video recording")

        guard !isRecording else {
            Log.p(Log.camera, Log.event, Log.error, "Cannot start recording - Already recording")
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
                    Log.p(Log.camera, Log.event, Log.error, "Cannot start recording - CameraManager deallocated")
                    continuation.resume(throwing: CameraError.recordingFailed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "CameraManager deallocated"])))
                    return
                }

                movieOutput?.startRecording(to: outputURL, recordingDelegate: self)
                currentRecordingURL = outputURL
                isRecording = true
                Log.p(Log.camera, Log.event, Log.success, "Recording started at: \(outputURL.path)")

                continuation.resume(returning: outputURL)
            }
        }
    }

    func stopRecording() async throws -> URL {
        Log.p(Log.camera, Log.stop, "Stopping video recording")

        guard isRecording, let outputURL = currentRecordingURL else {
            Log.p(Log.camera, Log.event, Log.error, "Cannot stop recording - Not currently recording")
            throw CameraError.recordingFailed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not recording"]))
        }

        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    Log.p(Log.camera, Log.event, Log.error, "Cannot stop recording - CameraManager deallocated")
                    continuation.resume(throwing: CameraError.recordingFailed(NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "CameraManager deallocated"])))
                    return
                }

                movieOutput?.stopRecording()
                Log.p(Log.camera, Log.event, "Stopping recording - URL will be returned in delegate callback")
                continuation.resume(returning: outputURL)
            }
        }
    }

    private var isAuthorized: Bool {
        get async {
            let status = AVCaptureDevice.authorizationStatus(for: .video)
            Log.p(Log.camera, Log.event, "Camera authorization status: \(status.rawValue)")

            switch status {
            case .authorized:
                Log.p(Log.camera, Log.event, Log.success, "Camera already authorized")
                return true

            case .notDetermined:
                Log.p(Log.camera, Log.event, "Requesting camera permission")
                do {
                    let granted = try await withCheckedThrowingContinuation { continuation in
                        AVCaptureDevice.requestAccess(for: .video) { granted in
                            Log.p(Log.camera, Log.event, "Permission request completed: \(granted)")
                            continuation.resume(returning: granted)
                        }
                    }
                    Log.p(Log.camera, Log.event, granted ? Log.success : Log.error, "Permission request result: \(granted)")
                    return granted
                } catch {
                    Log.p(Log.camera, Log.event, Log.error, "Permission request failed: \(error.localizedDescription)")
                    return false
                }

            case .denied:
                Log.p(Log.camera, Log.event, Log.error, "Camera permission denied")
                return false

            case .restricted:
                Log.p(Log.camera, Log.event, Log.error, "Camera access restricted")
                return false

            @unknown default:
                Log.p(Log.camera, Log.event, Log.error, "Unknown camera authorization status: \(status.rawValue)")
                return false
            }
        }
    }

    override private init() {
        super.init()
        Log.p(Log.camera, Log.start, "Initializing CameraManager")
    }

    func prepareAndStart() async {
        Log.p(Log.camera, Log.start, "Starting camera setup")
        await configureSession()
        await startSession()
    }

    func switchCamera() async {
        Log.p(Log.camera, Log.start, "Switching camera")

        do {
            // Stop the current session first
            stopSession()

            // Toggle camera position
            isFrontCameraActive.toggle()
            Log.p(Log.camera, Log.event, "Switching to \(isFrontCameraActive ? "front" : "back") camera")

            // Wait a brief moment to ensure cleanup
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

            // Configure and start new session
            await configureSession()
            await startSession()

            Log.p(Log.camera, Log.event, Log.success, "Camera switch completed successfully")
        } catch {
            Log.p(Log.camera, Log.event, Log.error, "Camera switch failed: \(error.localizedDescription)")

            // Try to recover by reverting to previous camera
            isFrontCameraActive.toggle()
            Log.p(Log.camera, Log.event, "Attempting recovery by reverting to previous camera")
            await configureSession()
            await startSession()
        }

        Log.p(Log.camera, Log.exit, "Camera switch operation complete")
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
        Log.p(Log.camera, Log.start, "Configuring camera session")

        guard await isAuthorized else {
            Log.p(Log.camera, Log.event, Log.error, "Cannot configure session - Camera not authorized")
            return
        }

        do {
            // Stop previous session if running
            stopSession()

            // Wait briefly for cleanup
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds

            guard let camera = getCurrentCamera() else {
                Log.p(Log.camera, Log.event, Log.error, "No camera device available")
                return
            }

            let deviceInput = try createDeviceInput(from: camera)
            let videoOutput = createVideoOutput()

            try configureSessionComponents(deviceInput: deviceInput, videoOutput: videoOutput)
            configureVideoConnection(for: videoOutput)

            self.deviceInput = deviceInput
            self.videoOutput = videoOutput
            Log.p(Log.camera, Log.event, Log.success, "Successfully configured session with new camera")
        } catch {
            Log.p(Log.camera, Log.event, Log.error, "Failed to configure session: \(error.localizedDescription)")
        }

        Log.p(Log.camera, Log.exit, "Session configuration complete")
    }

    private func createDeviceInput(from camera: AVCaptureDevice) throws -> AVCaptureDeviceInput {
        let deviceInput = try AVCaptureDeviceInput(device: camera)
        Log.p(Log.camera, Log.event, "Created device input")
        return deviceInput
    }

    private func createVideoOutput() -> AVCaptureVideoDataOutput {
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        Log.p(Log.camera, Log.event, "Created video output")
        return videoOutput
    }

    private func configureSessionComponents(
        deviceInput: AVCaptureDeviceInput,
        videoOutput: AVCaptureVideoDataOutput
    ) throws {
        captureSession.beginConfiguration()
        defer {
            captureSession.commitConfiguration()
            Log.p(Log.camera, Log.event, "Committed session configuration")
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
            Log.p(Log.camera, Log.event, Log.error, "Cannot add input to session")
            throw CameraError.setupFailed(setupError)
        }

        guard captureSession.canAddOutput(videoOutput) else {
            Log.p(Log.camera, Log.event, Log.error, "Cannot add output to session")
            throw CameraError.setupFailed(setupError)
        }

        // Configure movie output
        let movieOutput = AVCaptureMovieFileOutput()
        guard captureSession.canAddOutput(movieOutput) else {
            Log.p(Log.camera, Log.event, Log.error, "Cannot add movie output to session")
            throw CameraError.setupFailed(setupError)
        }

        captureSession.addInput(deviceInput)
        captureSession.addOutput(videoOutput)
        captureSession.addOutput(movieOutput)
        self.movieOutput = movieOutput
        Log.p(Log.camera, Log.event, Log.success, "Successfully added all inputs and outputs to session")
    }

    private func configureVideoConnection(for videoOutput: AVCaptureVideoDataOutput) {
        guard let connection = videoOutput.connection(with: .video) else {
            Log.p(Log.camera, Log.event, Log.warning, "No video connection available")
            return
        }

        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = isFrontCameraActive
            Log.p(Log.camera, Log.event, "Video mirroring configured: \(isFrontCameraActive)")
        }
        // Set rotation to portrait (90 degrees)
        connection.videoRotationAngle = 90
        Log.p(Log.camera, Log.event, "Video rotation set to portrait (90°)")
    }

    private func startSession() async {
        Log.p(Log.camera, Log.start, "Starting camera session")

        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else {
                    Log.p(Log.camera, Log.event, Log.error, "Cannot start session - CameraManager deallocated")
                    continuation.resume()
                    return
                }

                if !captureSession.isRunning {
                    captureSession.startRunning()
                    Log.p(Log.camera, Log.event, Log.success, "Camera session started successfully")
                } else {
                    Log.p(Log.camera, Log.event, Log.warning, "Session already running")
                }

                continuation.resume()
            }
        }
    }

    func stopSession() {
        Log.p(Log.camera, Log.stop, "Stopping camera session")

        sessionQueue.async { [weak self] in
            guard let self else {
                Log.p(Log.camera, Log.event, Log.error, "Cannot stop session - CameraManager deallocated")
                return
            }

            if captureSession.isRunning {
                captureSession.stopRunning()
                Log.p(Log.camera, Log.event, "Camera session stopped")
            } else {
                Log.p(Log.camera, Log.event, Log.warning, "Session already stopped")
            }

            // Clear existing inputs and outputs
            captureSession.beginConfiguration()
            captureSession.inputs.forEach { self.captureSession.removeInput($0) }
            captureSession.outputs.forEach { self.captureSession.removeOutput($0) }
            captureSession.commitConfiguration()
            Log.p(Log.camera, Log.event, "Cleared all inputs and outputs")

            // Clear references
            deviceInput = nil
            videoOutput = nil
            movieOutput = nil
            Log.p(Log.camera, Log.event, "Cleared all component references")
        }

        Log.p(Log.camera, Log.exit, "Session stop operation complete")
    }

    func reset() {
        Log.p(Log.camera, Log.start, "Resetting camera manager")
        stopSession()
        Log.p(Log.camera, Log.exit, "Camera manager reset complete")
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from _: AVCaptureConnection
    ) {
        guard let currentFrame = sampleBuffer.cgImage else {
            Log.p(Log.camera, Log.event, Log.warning, "Failed to get CGImage from sample buffer")
            return
        }
        addToPreviewStream?(currentFrame)
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from _: [AVCaptureConnection], error: Error?) {
        Log.p(Log.camera, Log.event, "Recording finished")

        isRecording = false
        currentRecordingURL = nil

        if let error {
            Log.p(Log.camera, Log.event, Log.error, "Recording failed: \(error.localizedDescription)")
        } else {
            Log.p(Log.camera, Log.event, Log.success, "Recording completed successfully at: \(outputFileURL.path)")
        }

        Log.p(Log.camera, Log.exit, "Recording cleanup complete")
    }

    func fileOutput(_: AVCaptureFileOutput, didStartRecordingTo outputURL: URL, from _: [AVCaptureConnection]) {
        Log.p(Log.camera, Log.event, Log.success, "Started recording to: \(outputURL.path)")
    }
}
