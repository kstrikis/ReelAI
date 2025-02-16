import SwiftUI
import FirebaseFirestore
import FirebaseAuth
import AVFoundation
import AVKit

struct ClipMakerView: View {
    let stories: [Story]
    @State private var selectedStory: Story?
    @State private var selectedScene: StoryScene?
    @State private var isGenerating = false
    @State private var error: Error?
    @State private var showError = false
    
    var body: some View {
        ZStack {
            SpaceBackground()
            
            ScrollView {
                VStack(spacing: 20) {
                    if stories.isEmpty {
                        Text("No stories found")
                            .foregroundColor(.gray)
                            .padding()
                    } else {
                        ForEach(stories) { story in
                            StoryCard(story: story, selectedStory: $selectedStory)
                        }
                    }
                }
                .padding()
            }
        }
        .sheet(item: $selectedStory) { story in
            SceneListView(
                story: story,
                selectedScene: $selectedScene,
                isGenerating: $isGenerating
            )
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "Unknown error occurred")
        }
    }
}

private struct StoryCard: View {
    let story: Story
    @Binding var selectedStory: Story?
    
    var body: some View {
        Button {
            selectedStory = story
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                Text(story.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text("Created: \(story.createdAt.formatted())")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text("\(story.scenes.count) scenes")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.gray.opacity(0.2))
            .cornerRadius(12)
        }
    }
}

private struct SceneListView: View {
    let story: Story
    @Binding var selectedScene: StoryScene?
    @Binding var isGenerating: Bool
    @Environment(\.dismiss) private var dismiss
    @StateObject private var videoService = VideoService.shared
    @State private var isRechecking = false
    
    var body: some View {
        NavigationView {
            ZStack {
                SpaceBackground()
                
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(story.scenes) { scene in
                            SceneCard(
                                scene: scene,
                                storyId: story.id,
                                isGenerating: videoService.isGenerating(for: scene.id),
                                onGenerate: { duration in
                                    Task {
                                        await generateClip(for: scene, duration: duration)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Scenes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await recheckVideos()
                        }
                    } label: {
                        if isRechecking {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isRechecking)
                }
            }
        }
    }
    
    private func generateClip(for scene: StoryScene, duration: Double) async {
        Log.p(Log.video, Log.event, "Generating clip with parameters - storyId: \(story.id), sceneId: \(scene.id), promptLength: \(scene.visualPrompt.count), duration: \(duration)")
        
        // Validate parameters
        guard !scene.visualPrompt.isEmpty else {
            Log.p(Log.video, Log.event, Log.error, "Cannot generate clip: Visual prompt is empty")
            return
        }
        
        guard duration >= 1 && duration <= 10 else {
            Log.p(Log.video, Log.event, Log.error, "Cannot generate clip: Duration must be between 1 and 10 seconds")
            return
        }
        
        do {
            try await videoService.generateClip(
                storyId: story.id,
                sceneId: scene.id,
                prompt: scene.visualPrompt,
                duration: duration
            )
        } catch {
            Log.p(Log.video, Log.event, Log.error, "Failed to generate clip: \(error.localizedDescription)")
        }
    }
    
    private func recheckVideos() async {
        guard !isRechecking else { return }
        
        isRechecking = true
        do {
            try await videoService.recheckVideos(storyId: story.id)
        } catch {
            Log.p(Log.video, Log.event, Log.error, "Failed to recheck videos: \(error.localizedDescription)")
        }
        isRechecking = false
    }
}

private struct Clip: Identifiable, Hashable {
    let id: String
    let sceneId: String
    let displayName: String
    let status: String
    let aimlapiUrl: String?
    let mediaUrl: String?
    let createdAt: Date
    
    static func == (lhs: Clip, rhs: Clip) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct SceneCard: View {
    let scene: StoryScene
    let storyId: String
    let isGenerating: Bool
    let onGenerate: (Double) -> Void
    @State private var showDurationControls = false
    @State private var narrationDuration: Double?
    @State private var soundEffectDuration: Double?
    @State private var isLoadingDurations = false
    @State private var selectedClip: Clip?
    @State private var isPlayingClip = false
    @State private var videoPlayer: AVPlayer?
    private let db = Firestore.firestore()
    @State private var clips: [Clip] = []
    @State private var isLoadingClips = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SceneHeader(scene: scene)
            
            if showDurationControls {
                DurationControlsView(
                    isLoading: isLoadingDurations,
                    narrationDuration: narrationDuration,
                    soundEffectDuration: soundEffectDuration,
                    sceneDuration: scene.duration,
                    onUpdateDuration: updateSceneDuration
                )
            }
            
            ClipPreviewView(
                isLoading: isLoadingClips,
                clips: clips,
                selectedClip: $selectedClip,
                isPlaying: isPlayingClip,
                videoPlayer: videoPlayer,
                onPlayback: toggleVideoPlayback
            )
            
            ControlButtonsView(
                showControls: showDurationControls,
                isGenerating: isGenerating,
                hasClips: !clips.isEmpty,
                sceneDuration: scene.duration,
                onToggleControls: {
                    if !showDurationControls { loadAudioDurations() }
                    if !clips.isEmpty { loadClips() }
                    showDurationControls.toggle()
                },
                onGenerate: onGenerate
            )
        }
        .padding()
        .background(Color.gray.opacity(0.2))
        .cornerRadius(12)
        .onAppear { loadClips() }
        .onDisappear { stopVideoPlayback() }
    }
    
    private func loadClips() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoadingClips = true
        clips = []
        
        Task {
            do {
                let clipsQuery = db.collection("users")
                    .document(userId)
                    .collection("stories")
                    .document(storyId)
                    .collection("videos")
                    .whereField("sceneId", isEqualTo: scene.id)
                
                let clipsResults = try await clipsQuery.getDocuments()
                
                await MainActor.run {
                    clips = clipsResults.documents.compactMap { doc in
                        let data = doc.data()
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateStyle = .short
                        dateFormatter.timeStyle = .short
                        let timestamp = dateFormatter.string(from: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date())
                        
                        return Clip(
                            id: doc.documentID,
                            sceneId: data["sceneId"] as? String ?? "",
                            displayName: "Scene \(scene.sceneNumber) (\(timestamp))",
                            status: data["status"] as? String ?? "pending",
                            aimlapiUrl: data["aimlapiUrl"] as? String,
                            mediaUrl: data["mediaUrl"] as? String,
                            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                        )
                    }.sorted { $0.createdAt > $1.createdAt }
                    
                    if selectedClip == nil, let firstClip = clips.first {
                        selectedClip = firstClip
                    }
                    
                    isLoadingClips = false
                }
            } catch {
                Log.error(Log.video, error, "Failed to load clips")
                await MainActor.run {
                    isLoadingClips = false
                }
            }
        }
    }
    
    private func toggleVideoPlayback(url: String) {
        guard let videoURL = URL(string: url) else { return }
        
        if isPlayingClip {
            stopVideoPlayback()
        } else {
            startVideoPlayback(url: videoURL)
        }
    }
    
    private func startVideoPlayback(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        
        if videoPlayer == nil {
            videoPlayer = AVPlayer(playerItem: playerItem)
        } else {
            videoPlayer?.replaceCurrentItem(with: playerItem)
        }
        
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            isPlayingClip = false
        }
        
        videoPlayer?.play()
        isPlayingClip = true
    }
    
    private func stopVideoPlayback() {
        videoPlayer?.pause()
        videoPlayer?.seek(to: .zero)
        videoPlayer = nil
        isPlayingClip = false
    }
    
    private func loadAudioDurations() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoadingDurations = true
        narrationDuration = nil
        soundEffectDuration = nil
        
        // Query for all completed audio files for this scene
        Task {
            do {
                let audioQuery = db.collection("users")
                    .document(userId)
                    .collection("stories")
                    .document(storyId)
                    .collection("audio")
                    .whereField("sceneId", isEqualTo: scene.id)
                    .whereField("status", isEqualTo: "completed")
                
                let audioResults = try await audioQuery.getDocuments()
                
                // Filter and sort in memory
                let narrationDoc = audioResults.documents
                    .filter { $0.data()["type"] as? String == "narration" }
                    .sorted { 
                        ($0.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast > 
                        ($1.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast 
                    }
                    .first
                
                let soundEffectDoc = audioResults.documents
                    .filter { $0.data()["type"] as? String == "soundEffect" }
                    .sorted { 
                        ($0.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast > 
                        ($1.data()["createdAt"] as? Timestamp)?.dateValue() ?? Date.distantPast 
                    }
                    .first
                
                await MainActor.run {
                    if let narrationUrl = narrationDoc?.data()["mediaUrl"] as? String {
                        Task {
                            narrationDuration = try? await getAudioDuration(from: narrationUrl)
                        }
                    }
                    
                    if let soundEffectUrl = soundEffectDoc?.data()["mediaUrl"] as? String {
                        Task {
                            soundEffectDuration = try? await getAudioDuration(from: soundEffectUrl)
                        }
                    }
                    
                    isLoadingDurations = false
                }
            } catch {
                Log.error(Log.video, error, "Failed to load audio durations")
                await MainActor.run {
                    isLoadingDurations = false
                }
            }
        }
    }
    
    private func getAudioDuration(from urlString: String) async throws -> Double {
        guard let url = URL(string: urlString) else { throw NSError(domain: "Invalid URL", code: -1) }
        let asset = AVAsset(url: url)
        let duration = try await asset.load(.duration)
        return duration.seconds
    }
    
    private func updateSceneDuration(to duration: Double) {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        Task {
            do {
                let storyRef = db.collection("users")
                    .document(userId)
                    .collection("stories")
                    .document(storyId)
                
                // Get the current story to find the scene index
                let story = try await storyRef.getDocument(as: Story.self)
                guard let sceneIndex = story.scenes.firstIndex(where: { $0.id == scene.id }) else {
                    Log.error(Log.video, NSError(domain: "StoryError", code: -1), "Could not find scene in story")
                    return
                }
                
                // Create an updated scenes array
                var updatedScenes = story.scenes
                updatedScenes[sceneIndex] = StoryScene(
                    id: scene.id,
                    sceneNumber: scene.sceneNumber,
                    narration: scene.narration,
                    voice: scene.voice,
                    visualPrompt: scene.visualPrompt,
                    audioPrompt: scene.audioPrompt,
                    duration: duration
                )
                
                // Update the entire scenes array
                try await storyRef.updateData([
                    "scenes": updatedScenes.map { scene in
                        [
                            "id": scene.id,
                            "sceneNumber": scene.sceneNumber,
                            "narration": scene.narration as Any,
                            "voice": scene.voice as Any,
                            "visualPrompt": scene.visualPrompt,
                            "audioPrompt": scene.audioPrompt as Any,
                            "duration": scene.duration as Any
                        ]
                    }
                ])
                
                Log.p(Log.video, Log.update, Log.success, "Updated scene duration to \(duration)s")
            } catch {
                Log.error(Log.video, error, "Failed to update scene duration")
            }
        }
    }
}

private struct SceneHeader: View {
    let scene: StoryScene
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scene \(scene.sceneNumber)")
                .font(.headline)
                .foregroundColor(.white)
            
            Text(scene.visualPrompt)
                .font(.body)
                .foregroundColor(.gray)
                .lineLimit(3)
        }
    }
}

private struct DurationControlsView: View {
    let isLoading: Bool
    let narrationDuration: Double?
    let soundEffectDuration: Double?
    let sceneDuration: Double?
    let onUpdateDuration: (Double) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView("Loading audio durations...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                Group {
                    if let narrationDuration = narrationDuration {
                        Text("Narration: \(String(format: "%.1f", narrationDuration))s")
                            .foregroundColor(.gray)
                    }
                    if let soundEffectDuration = soundEffectDuration {
                        Text("Sound Effect: \(String(format: "%.1f", soundEffectDuration))s")
                            .foregroundColor(.gray)
                    }
                    Text("Current Scene Duration: \(String(format: "%.1f", sceneDuration ?? 0))s")
                        .foregroundColor(.white)
                }
                .font(.caption)
                
                if let narrationDuration = narrationDuration,
                   let soundEffectDuration = soundEffectDuration,
                   let maxDuration = max(narrationDuration, soundEffectDuration) as Double?,
                   maxDuration != sceneDuration {
                    Button {
                        onUpdateDuration(maxDuration)
                    } label: {
                        Text("Update Duration to \(String(format: "%.1f", maxDuration))s")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.5))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ClipPreviewView: View {
    let isLoading: Bool
    let clips: [Clip]
    @Binding var selectedClip: Clip?
    let isPlaying: Bool
    let videoPlayer: AVPlayer?
    let onPlayback: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isLoading {
                ProgressView("Loading clips...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else if !clips.isEmpty {
                ClipPickerView(
                    clips: clips,
                    selectedClip: $selectedClip,
                    isPlaying: isPlaying,
                    onPlayback: onPlayback
                )
                
                if isPlaying, let player = videoPlayer {
                    VideoPlayer(player: player)
                        .frame(height: 200)
                        .cornerRadius(8)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ClipPickerView: View {
    let clips: [Clip]
    @Binding var selectedClip: Clip?
    let isPlaying: Bool
    let onPlayback: (String) -> Void
    
    var body: some View {
        HStack {
            ClipPickerContent(clips: clips, selectedClip: $selectedClip)
            
            if let selectedClip = selectedClip {
                ClipStatusView(
                    clip: selectedClip,
                    isPlaying: isPlaying,
                    onPlayback: onPlayback
                )
            }
        }
    }
}

private struct ClipPickerContent: View {
    let clips: [Clip]
    @Binding var selectedClip: Clip?
    
    var body: some View {
        Picker("Select Clip", selection: $selectedClip) {
            ForEach(clips) { clip in
                ClipPickerRow(clip: clip)
                    .tag(clip as Clip?)
            }
        }
        .pickerStyle(.menu)
        .tint(.white)
        .background(Color.white.opacity(0.2))
        .cornerRadius(8)
    }
}

private struct ClipPickerRow: View {
    let clip: Clip
    
    var body: some View {
        Text(clip.displayName)
            .foregroundColor(clip.status == "completed" ? .white :
                           clip.status == "failed" ? .red :
                           .white.opacity(0.5))
    }
}

private struct ClipStatusView: View {
    let clip: Clip
    let isPlaying: Bool
    let onPlayback: (String) -> Void
    
    var body: some View {
        Group {
            if clip.status == "completed",
               let url = clip.mediaUrl {
                Button {
                    onPlayback(url)
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            } else if clip.status == "generating" || clip.status == "pending" {
                ProgressView()
                    .tint(.white)
            } else if clip.status == "failed" {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
    }
}

private struct ControlButtonsView: View {
    let showControls: Bool
    let isGenerating: Bool
    let hasClips: Bool
    let sceneDuration: Double?
    let onToggleControls: () -> Void
    let onGenerate: (Double) -> Void
    
    var body: some View {
        HStack {
            Button(action: onToggleControls) {
                HStack {
                    Image(systemName: showControls ? "clock.fill" : "clock")
                    Text(showControls ? "Hide Controls" : "Show Controls")
                }
                .font(.caption)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(6)
            }
            
            Spacer()
            
            Button {
                onGenerate(sceneDuration ?? 5.0)
            } label: {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Image(systemName: "video.fill")
                    }
                    Text(isGenerating ? "Generating..." : "Generate Clip")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .disabled(isGenerating)
        }
    }
}

#Preview {
    ClipMakerView(stories: Story.previewStories)
} 