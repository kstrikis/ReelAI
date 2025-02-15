import SwiftUI
import AVKit

private struct AudioVersion: Identifiable {
    let id: String
    let number: Int
    let audio: Audio
}

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
    @State private var selectedBGM: Audio?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var audioPlayer: AVPlayer?
    @State private var isPlaying = false
    
    private var backgroundMusicAudios: [Audio] {
        audioService.currentAudio.filter { $0.type == .backgroundMusic }
    }
    
    var body: some View {
        ZStack {
            SpaceBackground()
            mainContent
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
            if let firstBGM = backgroundMusicAudios.first {
                selectedBGM = firstBGM
            }
        }
    }
    
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                backgroundMusicSection
                scenesSection
            }
            .padding()
        }
    }
    
    private var backgroundMusicSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background Music")
                .font(.headline)
                .foregroundColor(.white)
            
            if let prompt = story.backgroundMusicPrompt {
                Text("Prompt: \(prompt)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
            
            if backgroundMusicAudios.isEmpty {
                generateBGMButton
            } else {
                bgmPlayerControls
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    private var generateBGMButton: some View {
        Button {
            generateAudio(for: story, type: .backgroundMusic)
        } label: {
            Label("Generate Background Music", systemImage: "music.note")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(isGenerating)
    }
    
    private var bgmPlayerControls: some View {
        HStack {
            bgmPicker
            playButton(isPlaying: isPlaying) {
                if let selectedBGM = selectedBGM {
                    Log.p(Log.audio_music, Log.event, "User tapped play for BGM: \(selectedBGM.id)")
                }
            }
        }
    }
    
    private var bgmPicker: some View {
        let versions = backgroundMusicAudios.enumerated().map { index, audio in
            AudioVersion(id: audio.id, number: index + 1, audio: audio)
        }
        return versionPicker(versions: versions, selection: $selectedBGM)
    }
    
    private func versionPicker(versions: [AudioVersion], selection: Binding<Audio?>) -> some View {
        Picker("Select Version", selection: selection) {
            ForEach(versions) { version in
                Text("Version \(version.number)")
                    .tag(version.audio as Audio?)
            }
        }
        .pickerStyle(.menu)
        .tint(.white)
        .background(Color.white.opacity(0.2))
        .cornerRadius(8)
    }
    
    private func playButton(isPlaying: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.title2)
                .foregroundColor(.white)
        }
    }
    
    private var scenesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scenes:")
                .font(.headline)
                .foregroundColor(.white)
            
            ForEach(story.scenes) { scene in
                NavigationLink {
                    SceneAudioView(story: story, scene: scene)
                } label: {
                    SceneAudioCard(scene: scene, audioService: audioService)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func generateAudio(
        for story: Story,
        type: Audio.AudioType,
        completion: @escaping (Result<Audio, AudioServiceError>) -> Void = { _ in }
    ) {
        guard let userId = authService.currentUser?.uid else {
            errorMessage = "No user logged in"
            showError = true
            return
        }
        
        isGenerating = true
        audioService.generateAudio(
            for: story,
            type: type,
            userId: userId
        ) { result in
            DispatchQueue.main.async {
                isGenerating = false
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
}

struct SceneAudioCard: View {
    let scene: StoryScene
    @ObservedObject var audioService: AudioService
    
    private var narrationCount: Int {
        audioService.currentAudio.filter { $0.type == .narration && $0.sceneId == scene.id }.count
    }
    
    private var soundEffectCount: Int {
        audioService.currentAudio.filter { $0.type == .soundEffect && $0.sceneId == scene.id }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scene \(scene.sceneNumber)")
                .font(.headline)
                .foregroundColor(.white)
            
            if let narration = scene.narration {
                Text(narration)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
            
            HStack(spacing: 16) {
                Label {
                    Text("\(narrationCount)")
                        .foregroundColor(narrationCount == 0 ? .blue : .green)
                } icon: {
                    Image(systemName: "waveform")
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Label {
                    Text("\(soundEffectCount)")
                        .foregroundColor(soundEffectCount == 0 ? .blue : .green)
                } icon: {
                    Image(systemName: "speaker.wave.3")
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .font(.caption)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
}

struct SceneAudioView: View {
    let story: Story
    let scene: StoryScene
    @StateObject private var audioService = AudioService()
    @EnvironmentObject private var authService: AuthenticationService
    @State private var selectedNarration: Audio?
    @State private var selectedSoundEffect: Audio?
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var isPlayingNarration = false
    @State private var isPlayingSoundEffect = false
    
    private var narrationAudios: [Audio] {
        audioService.currentAudio.filter { $0.type == .narration && $0.sceneId == scene.id }
    }
    
    private var soundEffectAudios: [Audio] {
        audioService.currentAudio.filter { $0.type == .soundEffect && $0.sceneId == scene.id }
    }
    
    var body: some View {
        ZStack {
            SpaceBackground()
            mainContent
        }
        .navigationTitle("Scene \(scene.sceneNumber) Audio")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .onAppear {
            audioService.loadAudio(for: story.userId, storyId: story.id)
            if let firstNarration = narrationAudios.first {
                selectedNarration = firstNarration
            }
            if let firstSoundEffect = soundEffectAudios.first {
                selectedSoundEffect = firstSoundEffect
            }
        }
    }
    
    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                audioSection(
                    title: "Narration",
                    prompt: scene.narration,
                    type: .narration,
                    audios: narrationAudios,
                    selectedAudio: $selectedNarration,
                    isPlaying: isPlayingNarration
                )
                
                audioSection(
                    title: "Sound Effects",
                    prompt: scene.audioPrompt,
                    type: .soundEffect,
                    audios: soundEffectAudios,
                    selectedAudio: $selectedSoundEffect,
                    isPlaying: isPlayingSoundEffect
                )
            }
            .padding()
        }
    }
    
    private func audioSection(
        title: String,
        prompt: String?,
        type: Audio.AudioType,
        audios: [Audio],
        selectedAudio: Binding<Audio?>,
        isPlaying: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: title, prompt: prompt)
            
            if audios.isEmpty {
                generateButton(for: type, title: title)
            } else {
                audioControls(
                    type: type,
                    audios: audios,
                    selectedAudio: selectedAudio,
                    isPlaying: isPlaying
                )
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func sectionHeader(title: String, prompt: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            
            if let prompt = prompt {
                Text("Prompt: \(prompt)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }
        }
    }
    
    private func generateButton(for type: Audio.AudioType, title: String) -> some View {
        Button {
            generateAudio(type: type)
        } label: {
            Label("Generate \(title)", systemImage: type == .narration ? "waveform" : "speaker.wave.3")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue.opacity(0.3))
                .foregroundColor(.white)
                .cornerRadius(12)
        }
        .disabled(isGenerating)
    }
    
    private func audioControls(
        type: Audio.AudioType,
        audios: [Audio],
        selectedAudio: Binding<Audio?>,
        isPlaying: Bool
    ) -> some View {
        HStack {
            audioPicker(audios: audios, selectedAudio: selectedAudio)
            playButton(isPlaying: isPlaying) {
                if let selected = selectedAudio.wrappedValue {
                    Log.p(Log.audio_music, Log.event, "User tapped play for \(type): \(selected.id)")
                }
            }
        }
    }
    
    private func audioPicker(audios: [Audio], selectedAudio: Binding<Audio?>) -> some View {
        let versions = audios.enumerated().map { index, audio in
            AudioVersion(id: audio.id, number: index + 1, audio: audio)
        }
        return versionPicker(versions: versions, selection: selectedAudio)
    }
    
    private func versionPicker(versions: [AudioVersion], selection: Binding<Audio?>) -> some View {
        Picker("Select Version", selection: selection) {
            ForEach(versions) { version in
                Text("Version \(version.number)")
                    .tag(version.audio as Audio?)
            }
        }
        .pickerStyle(.menu)
        .tint(.white)
        .background(Color.white.opacity(0.2))
        .cornerRadius(8)
    }
    
    private func playButton(isPlaying: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.title2)
                .foregroundColor(.white)
        }
    }
    
    private func generateAudio(type: Audio.AudioType) {
        guard let userId = authService.currentUser?.uid else {
            errorMessage = "No user logged in"
            showError = true
            return
        }
        
        isGenerating = true
        audioService.generateAudio(
            for: story,
            sceneId: scene.id,
            type: type,
            userId: userId
        ) { result in
            DispatchQueue.main.async {
                isGenerating = false
                switch result {
                case .success(let audio):
                    switch type {
                    case .narration:
                        selectedNarration = audio
                    case .soundEffect:
                        selectedSoundEffect = audio
                    default:
                        break
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                }
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