import SwiftUI
import AVKit

struct AudioMakerView: View {
    @StateObject private var audioService = AudioService()
    @EnvironmentObject private var authService: AuthenticationService
    
    private let stories: [Story]
    
    init(stories: [Story]) {
        self.stories = stories.sorted { $0.createdAt > $1.createdAt }
    }
    
    var body: some View {
        ZStack {
            SpaceBackground()
            
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(stories) { story in
                        StoryAudioCard(story: story, audioService: audioService)
                    }
                }
                .padding()
            }
        }
    }
}

struct StoryAudioCard: View {
    let story: Story
    @ObservedObject var audioService: AudioService
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    private var hasAllAudio: Bool {
        let existingAudio = Set(audioService.currentAudio.map { "\($0.type)_\($0.sceneId ?? "background")" })
        
        // Check background music
        if !existingAudio.contains("backgroundMusic_background") {
            return false
        }
        
        // Check each scene's narration and sound effects
        for scene in story.scenes {
            if !existingAudio.contains("narration_\(scene.id)") ||
               !existingAudio.contains("soundEffect_\(scene.id)") {
                return false
            }
        }
        
        return true
    }
    
    var body: some View {
        NavigationLink {
            AudioGeneratorView(story: story)
        } label: {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(story.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("\(story.scenes.count) scenes")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    Button {
                        generateAllMissingAudio()
                    } label: {
                        HStack {
                            Image(systemName: hasAllAudio ? "checkmark" : "wand.and.stars")
                            Text(hasAllAudio ? "Complete" : "Generate")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(hasAllAudio ? Color.green.opacity(0.3) : Color.blue.opacity(0.3))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(hasAllAudio ? Color.green.opacity(0.5) : Color.blue.opacity(0.5), lineWidth: 1)
                        )
                    }
                    .disabled(isGenerating || hasAllAudio)
                }
                
                if isGenerating {
                    ProgressView()
                        .tint(.white)
                }
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .alert("Error", isPresented: $showError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .onAppear {
            audioService.loadAudio(for: story.userId, storyId: story.id)
        }
    }
    
    private func generateAllMissingAudio() {
        let userId = story.userId
        
        // Create a set of existing audio IDs for quick lookup
        let existingAudio = Set(audioService.currentAudio.map { "\($0.type)_\($0.sceneId ?? "background")" })
        
        var generationsRemaining = 0
        
        // Queue up background music if missing
        if !existingAudio.contains("backgroundMusic_background") {
            generationsRemaining += 1
            audioService.generateAudio(
                for: story,
                type: .backgroundMusic,
                userId: userId
            ) { result in
                handleGenerationComplete(result)
            }
        }
        
        // Queue up narration and sound effects for each scene
        for scene in story.scenes {
            if !existingAudio.contains("narration_\(scene.id)") {
                generationsRemaining += 1
                audioService.generateAudio(
                    for: story,
                    sceneId: scene.id,
                    type: .narration,
                    userId: userId
                ) { result in
                    handleGenerationComplete(result)
                }
            }
            if !existingAudio.contains("soundEffect_\(scene.id)") {
                generationsRemaining += 1
                audioService.generateAudio(
                    for: story,
                    sceneId: scene.id,
                    type: .soundEffect,
                    userId: userId
                ) { result in
                    handleGenerationComplete(result)
                }
            }
        }
        
        if generationsRemaining == 0 {
            isGenerating = false
        }
    }
    
    private func handleGenerationComplete(_ result: Result<Audio, AudioServiceError>) {
        DispatchQueue.main.async {
            switch result {
            case .success:
                break
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
            isGenerating = false
        }
    }
}

// Move the existing detail view into a new AudioGeneratorView
struct AudioGeneratorView: View {
    @StateObject private var audioService = AudioService()
    @EnvironmentObject private var authService: AuthenticationService
    
    let story: Story
    @State private var selectedScene: StoryScene?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var audioPlayer: AVPlayer?
    @State private var isPlaying = false
    
    var body: some View {
        ZStack {
            SpaceBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Scene Selection (if applicable)
                    sceneSelectionSection
                    
                    // Audio Generation Controls
                    audioControlsSection(for: story)
                    
                    // Generated Audio List
                    audioListSection(for: story)
                }
                .padding()
            }
        }
        .navigationTitle(story.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .onAppear {
            audioService.loadAudio(for: story.userId, storyId: story.id)
        }
    }
    
    private var sceneSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select a Scene (Optional)")
                .font(.headline)
                .foregroundColor(.white)
            
            Picker("Scene", selection: $selectedScene) {
                Text("Background Music").tag(nil as StoryScene?)
                ForEach(story.scenes) { scene in
                    Text("Scene \(scene.sceneNumber)").tag(scene as StoryScene?)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)
        }
        .padding(.vertical)
    }
    
    private func audioControlsSection(for story: Story) -> some View {
        VStack(spacing: 16) {
            // Background Music Generation
            Button {
                generateAudio(for: story, type: .backgroundMusic)
            } label: {
                Label("Generate Background Music", systemImage: "music.note")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.2))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .disabled(isGenerating)
            
            if let scene = selectedScene {
                // Narration Generation
                Button {
                    generateAudio(for: story, sceneId: scene.id, type: .narration)
                } label: {
                    Label("Generate Narration", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.2))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(isGenerating)
                
                // Sound Effects Generation
                Button {
                    generateAudio(for: story, sceneId: scene.id, type: .soundEffect)
                } label: {
                    Label("Generate Sound Effects", systemImage: "speaker.wave.3")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.white.opacity(0.2))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(isGenerating)
            }
        }
        .padding(.vertical)
    }
    
    private func audioListSection(for story: Story) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Generated Audio")
                .font(.headline)
                .foregroundColor(.white)
            
            ForEach(audioService.currentAudio) { audio in
                AudioItemView(audio: audio, isPlaying: isPlaying) {
                    // Play/pause functionality will be implemented later
                    Log.p(Log.audio_music, Log.event, "User tapped play for audio: \(audio.id)")
                }
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
            }
        }
        .padding(.vertical)
    }
    
    private func generateAudio(
        for story: Story,
        sceneId: String? = nil,
        type: Audio.AudioType,
        completion: @escaping (Result<Audio, AudioServiceError>) -> Void = { _ in }
    ) {
        guard let userId = authService.currentUser?.uid else {
            errorMessage = "No user logged in"
            showError = true
            return
        }
        
        audioService.generateAudio(
            for: story,
            sceneId: sceneId,
            type: type,
            userId: userId
        ) { result in
            switch result {
            case .success(let audio):
                completion(.success(audio))
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
                completion(.failure(error))
            }
        }
    }
}

struct AudioItemView: View {
    let audio: Audio
    let isPlaying: Bool
    let onTap: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text(audio.type.rawValue.capitalized)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(audio.prompt)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
            
            Spacer()
            
            switch audio.status {
            case .pending:
                ProgressView()
                    .tint(.white)
            case .generating:
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            case .completed:
                Button {
                    onTap()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                }
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding()
    }
}

#Preview {
    AudioMakerView(stories: [
        Story(
            id: "story_1",
            title: "Test Story",
            template: "test",
            backgroundMusicPrompt: "Spooky music",
            scenes: [
                StoryScene(
                    id: "scene_1",
                    sceneNumber: 1,
                    narration: "Once upon a time...",
                    voice: "ElevenLabs Adam",
                    visualPrompt: "A dark forest",
                    audioPrompt: "Wind howling",
                    duration: 5.0
                )
            ],
            createdAt: Date(),
            userId: "user_1"
        )
    ])
    .environmentObject(AuthenticationService.preview)
} 