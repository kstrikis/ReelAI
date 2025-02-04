import SwiftUI
import AVFoundation

// MARK: - Camera Errors
enum CameraError: LocalizedError {
    case deviceNotAvailable
    case setupFailed(Error)
    case outputNotAvailable
    case recordingFailed(Error)
    
    var errorDescription: String? {
        switch self {
            case .deviceNotAvailable: return "Failed to get video device"
            case .setupFailed(let error): return "Failed to setup camera session: \(error.localizedDescription)"
            case .outputNotAvailable: return "Video output not available"
            case .recordingFailed(let error): return "Recording failed: \(error.localizedDescription)"
        }
    }
}

@Observable
final class CameraViewModel {
    var currentFrame: CGImage?
    private let cameraManager = CameraManager.shared
    
    init() {
        AppLogger.methodEntry(AppLogger.ui)
        AppLogger.methodExit(AppLogger.ui)
    }
    
    func handleCameraPreviews() async {
        AppLogger.methodEntry(AppLogger.ui)
        await cameraManager.prepareAndStart()
        for await image in cameraManager.previewStream {
            Task { @MainActor in
                currentFrame = image
            }
        }
        AppLogger.methodExit(AppLogger.ui)
    }
    
    func stopCamera() {
        AppLogger.methodEntry(AppLogger.ui)
        cameraManager.stopSession()
        AppLogger.methodExit(AppLogger.ui)
    }
}

struct CameraRecordingView: View {
    let isActive: Bool
    @State private var viewModel = CameraViewModel()
    @State private var isRecording = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview
                if let image = viewModel.currentFrame {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    ContentUnavailableView("No camera feed", systemImage: "video.slash")
                }
                
                // Controls overlay
                VStack {
                    // Top controls
                    HStack {
                        Spacer()
                        Button(action: {
                            Task {
                                await CameraManager.shared.switchCamera()
                            }
                        }) {
                            Image(systemName: "camera.rotate")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                    .padding(.top, 10)
                    
                    Spacer()
                    
                    // Bottom controls
                    HStack {
                        Spacer()
                        
                        // Record button
                        Button(action: toggleRecording) {
                            Circle()
                                .fill(isRecording ? Color.red : Color.white)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 4)
                                        .frame(width: 70, height: 70)
                                )
                        }
                        
                        Spacer()
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .ignoresSafeArea()
        .onChange(of: isActive) { wasActive, isNowActive in
            if isNowActive {
                // Start camera when swiping to this view
                Task {
                    await viewModel.handleCameraPreviews()
                }
            } else {
                // Stop camera when swiping away
                viewModel.stopCamera()
            }
        }
    }
    
    private func toggleRecording() {
        AppLogger.methodEntry(AppLogger.ui)
        withAnimation {
            isRecording.toggle()
            // TODO: Implement actual video recording
        }
        AppLogger.methodExit(AppLogger.ui)
    }
}

#if DEBUG
struct CameraRecordingView_Previews: PreviewProvider {
    static var previews: some View {
        CameraRecordingView(isActive: true)
    }
}
#endif 