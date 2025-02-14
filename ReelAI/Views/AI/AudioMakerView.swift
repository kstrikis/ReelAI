import SwiftUI
import AVKit

struct AudioMakerView: View {
    @StateObject private var audioService = AudioService()
    @EnvironmentObject private var authService: AuthenticationService
    
    @State private var selectedStory: Story?
    @State private var selectedScene: StoryScene?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var audioPlayer: AVPlayer?
    @State private var isPlaying = false
    
    private let stories: [Story]
    
    init(stories: [Story]) {
        self.stories = stories
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Story Selection
            storySelectionSection
            
            if let story = selectedStory {
                // Scene Selection (if applicable)
                sceneSelectionSection(for: story)
                
                // Audio Generation Controls
                audioControlsSection(for: story)
                
                // Generated Audio List
                audioListSection(for: story)
            }
        }
        .padding()
        .alert("Error", isPresented: $showError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .onChange(of: selectedStory) { _, newStory in
            if let story = newStory,
               let userId = authService.currentUser?.uid {
                audioService.loadAudio(for: userId, storyId: story.id)
            }
        }
    }
    
    private var storySelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select a Story")
                .font(.headline)
            
            Picker("Story", selection: $selectedStory) {
                Text("Choose a story").tag(nil as Story?)
                ForEach(stories) { story in
                    Text(story.title).tag(story as Story?)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private func sceneSelectionSection(for story: Story) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select a Scene (Optional)")
                .font(.headline)
            
            Picker("Scene", selection: $selectedScene) {
                Text("Background Music").tag(nil as StoryScene?)
                ForEach(story.scenes) { scene in
                    Text("Scene \(scene.sceneNumber)").tag(scene as StoryScene?)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private func audioControlsSection(for story: Story) -> some View {
        VStack(spacing: 12) {
            // Background Music Generation
            Button {
                generateAudio(for: story, type: .backgroundMusic)
            } label: {
                Label("Generate Background Music", systemImage: "music.note")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isGenerating)
            
            if let scene = selectedScene {
                // Narration Generation
                Button {
                    generateAudio(for: story, sceneId: scene.id, type: .narration)
                } label: {
                    Label("Generate Narration", systemImage: "waveform")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
                
                // Sound Effects Generation
                Button {
                    generateAudio(for: story, sceneId: scene.id, type: .soundEffect)
                } label: {
                    Label("Generate Sound Effects", systemImage: "speaker.wave.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isGenerating)
            }
        }
    }
    
    private func audioListSection(for story: Story) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generated Audio")
                .font(.headline)
            
            List(audioService.currentAudio) { audio in
                AudioItemView(audio: audio, isPlaying: isPlaying) {
                    // Play/pause functionality will be implemented later
                    Log.p(Log.ai_audio, Log.event, "User tapped play for audio: \(audio.id)")
                }
            }
            .listStyle(.plain)
        }
    }
    
    private func generateAudio(for story: Story, sceneId: String? = nil, type: Audio.AudioType) {
        guard let userId = authService.currentUser?.uid else {
            errorMessage = "No user logged in"
            showError = true
            return
        }
        
        isGenerating = true
        
        audioService.generateAudio(
            for: story,
            sceneId: sceneId,
            type: type,
            userId: userId
        ) { result in
            isGenerating = false
            
            switch result {
            case .success:
                // Audio metadata created successfully
                break
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
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
            VStack(alignment: .leading) {
                Text(audio.type.rawValue.capitalized)
                    .font(.headline)
                Text(audio.prompt)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            switch audio.status {
            case .pending:
                ProgressView()
            case .generating:
                ProgressView()
                    .progressViewStyle(.circular)
            case .completed:
                Button {
                    onTap()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .padding(.vertical, 8)
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