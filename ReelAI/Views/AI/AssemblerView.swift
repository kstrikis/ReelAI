import SwiftUI
import AVKit
import FirebaseFirestore
import FirebaseFunctions
import Photos

struct AssemblerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthenticationService
    @StateObject private var audioService = AudioService()
    
    let stories: [Story]
    @State private var selectedStory: Story?
    @State private var isAssembling = false
    @State private var assemblies: [Assembly] = []
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var player: AVPlayer?
    @State private var isPlayingPreview = false
    
    // Audio and video selection states
    @State private var selectedBGM: Audio?
    @State private var selectedNarrations: [String: Audio] = [:]
    @State private var selectedSoundEffects: [String: Audio] = [:]
    @State private var selectedClips: [String: Clip] = [:]
    
    private let db = Firestore.firestore()
    
    private var backgroundMusicAudios: [Audio] {
        audioService.currentAudio.filter { $0.type == .backgroundMusic && $0.storyId == selectedStory?.id }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    var body: some View {
        ZStack {
            SpaceBackground()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Story Selector
                    Picker("Select Story", selection: $selectedStory) {
                        Text("Select a Story").tag(nil as Story?)
                        ForEach(stories) { story in
                            Text(story.title).tag(story as Story?)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding()
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(10)
                    
                    if let story = selectedStory {
                        // Story Details
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Story: \(story.title)")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Text("Scenes: \(story.scenes.count)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            // Background Music Picker
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Background Music")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                if backgroundMusicAudios.isEmpty {
                                    Text("No background music available")
                                        .foregroundColor(.gray)
                                } else {
                                    Picker("Select Background Music", selection: $selectedBGM) {
                                        Text("None").tag(nil as Audio?)
                                        ForEach(backgroundMusicAudios) { audio in
                                            Text(audio.displayName)
                                                .tag(audio as Audio?)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                    .tint(.white)
                                }
                            }
                            .padding()
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                            
                            // Scene Pickers
                            ForEach(story.scenes) { scene in
                                ScenePickerView(
                                    story: story,
                                    scene: scene,
                                    audioService: audioService,
                                    selectedNarration: selectedNarrationBinding(for: scene.id),
                                    selectedSoundEffect: selectedSoundEffectBinding(for: scene.id),
                                    selectedClip: selectedClipBinding(for: scene.id)
                                )
                            }
                            
                            // Assembly Button
                            Button {
                                Task {
                                    await assembleVideo()
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "film.stack")
                                    Text("Assemble Video")
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(isAssembling || !canAssemble)
                            
                            if isAssembling {
                                ProgressView("Assembling video...")
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                        
                        // Assemblies List
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Previous Assemblies")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                            
                            ForEach(assemblies) { assembly in
                                AssemblyCard(assembly: assembly, player: $player, isPlayingPreview: $isPlayingPreview)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Assembler")
        .alert("Error", isPresented: $showError, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(errorMessage ?? "An unknown error occurred")
        })
        .onChange(of: selectedStory) { story in
            if let story = story {
                loadAssemblies(for: story)
                Task {
                    await audioService.loadAudio(for: story.userId, storyId: story.id)
                    // Auto-select the most recent background music
                    selectedBGM = backgroundMusicAudios.first
                }
            }
        }
        .onChange(of: audioService.currentAudio) { _ in
            // Auto-select the most recent background music if none is selected
            if selectedBGM == nil {
                selectedBGM = backgroundMusicAudios.first
            }
        }
        .onDisappear {
            // Stop any playing video
            player?.pause()
            player = nil
        }
    }
    
    private var canAssemble: Bool {
        guard let story = selectedStory else { return false }
        
        // Check if all scenes have required media
        return story.scenes.allSatisfy { scene in
            selectedClips[scene.id] != nil &&
            selectedNarrations[scene.id] != nil
        }
    }
    
    private func selectedNarrationBinding(for sceneId: String) -> Binding<Audio?> {
        Binding(
            get: { selectedNarrations[sceneId] },
            set: { selectedNarrations[sceneId] = $0 }
        )
    }
    
    private func selectedSoundEffectBinding(for sceneId: String) -> Binding<Audio?> {
        Binding(
            get: { selectedSoundEffects[sceneId] },
            set: { selectedSoundEffects[sceneId] = $0 }
        )
    }
    
    private func selectedClipBinding(for sceneId: String) -> Binding<Clip?> {
        Binding(
            get: { selectedClips[sceneId] },
            set: { selectedClips[sceneId] = $0 }
        )
    }
    
    private func assembleVideo() async {
        guard let story = selectedStory else { return }
        
        isAssembling = true
        
        do {
            // Collect all completed clips for this story
            let clips = story.scenes.compactMap { scene -> [String: Any]? in
                guard let clip = selectedClips[scene.id],
                      let narration = selectedNarrations[scene.id],
                      let videoUrl = clip.mediaUrl,
                      let audioUrl = narration.mediaUrl else {
                    return nil
                }
                
                var clipData: [String: Any] = [
                    "sceneId": scene.id,
                    "videoUrl": videoUrl,
                    "audioUrl": audioUrl
                ]
                
                // Add sound effect if available
                if let soundEffect = selectedSoundEffects[scene.id],
                   let sfxUrl = soundEffect.mediaUrl {
                    clipData["soundEffectUrl"] = sfxUrl
                }
                
                return clipData
            }
            
            // Call the Cloud Function with clips data
            let functions = Functions.functions()
            let result = try await functions.httpsCallable("assembleVideo").call([
                "storyId": story.id,
                "clips": clips,
                "backgroundMusicUrl": selectedBGM?.mediaUrl
            ])
            
            guard let data = result.data as? [String: Any],
                  let success = data["success"] as? Bool,
                  success else {
                throw NSError(
                    domain: "AssemblerError",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid response format"]
                )
            }
            
            // Reload assemblies
            loadAssemblies(for: story)
            
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        
        isAssembling = false
    }
    
    private func loadAssemblies(for story: Story) {
        guard let userId = authService.currentUser?.uid else { return }
        
        // Clear existing assemblies
        assemblies = []
        
        // Listen for assemblies
        db.collection("users")
            .document(userId)
            .collection("stories")
            .document(story.id)
            .collection("assemblies")
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    Log.error(Log.video, error, "Error loading assemblies")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    Log.p(Log.video, Log.read, "No assemblies found")
                    return
                }
                
                assemblies = documents.compactMap { doc -> Assembly? in
                    let data = doc.data()
                    
                    guard let id = data["id"] as? String,
                          let storyId = data["storyId"] as? String,
                          let userId = data["userId"] as? String,
                          let displayName = data["displayName"] as? String,
                          let status = data["status"] as? String,
                          let timestamp = data["createdAt"] as? Timestamp else {
                        return nil
                    }
                    
                    return Assembly(
                        id: id,
                        storyId: storyId,
                        userId: userId,
                        displayName: displayName,
                        status: status,
                        mediaUrl: data["mediaUrl"] as? String,
                        createdAt: timestamp.dateValue()
                    )
                }
            }
    }
}

struct ScenePickerView: View {
    let story: Story
    let scene: StoryScene
    let audioService: AudioService
    @Binding var selectedNarration: Audio?
    @Binding var selectedSoundEffect: Audio?
    @Binding var selectedClip: Clip?
    @State private var isLoadingClips = false
    @State private var clips: [Clip] = []
    @State private var narrations: [Audio] = []
    @State private var soundEffects: [Audio] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scene \(scene.sceneNumber)")
                .font(.headline)
                .foregroundColor(.white)
            
            // Narration Picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Narration")
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                if narrations.isEmpty {
                    Text("No narration available")
                        .foregroundColor(.gray)
                } else {
                    Picker("Select Narration", selection: $selectedNarration) {
                        Text("None").tag(nil as Audio?)
                        ForEach(narrations) { audio in
                            Text(audio.displayName)
                                .tag(audio as Audio?)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                }
            }
            
            // Sound Effect Picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Sound Effect")
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                if soundEffects.isEmpty {
                    Text("No sound effects available")
                        .foregroundColor(.gray)
                } else {
                    Picker("Select Sound Effect", selection: $selectedSoundEffect) {
                        Text("None").tag(nil as Audio?)
                        ForEach(soundEffects) { audio in
                            Text(audio.displayName)
                                .tag(audio as Audio?)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                }
            }
            
            // Clip Picker
            VStack(alignment: .leading, spacing: 4) {
                Text("Video Clip")
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                if isLoadingClips {
                    ProgressView()
                        .tint(.white)
                } else if clips.isEmpty {
                    Text("No clips available")
                        .foregroundColor(.gray)
                } else {
                    Picker("Select Clip", selection: $selectedClip) {
                        Text("None").tag(nil as Clip?)
                        ForEach(clips) { clip in
                            Text(clip.displayName)
                                .tag(clip as Clip?)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.white)
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(10)
        .onAppear {
            loadClips()
            updateAudioArrays()
        }
        .onChange(of: audioService.currentAudio) { _ in
            updateAudioArrays()
        }
        .onChange(of: clips) { newClips in
            if selectedClip == nil {
                selectedClip = newClips.first
            }
        }
        .onChange(of: narrations) { newNarrations in
            if selectedNarration == nil {
                selectedNarration = newNarrations.first
            }
        }
        .onChange(of: soundEffects) { newSoundEffects in
            if selectedSoundEffect == nil {
                selectedSoundEffect = newSoundEffects.first
            }
        }
    }
    
    private func updateAudioArrays() {
        narrations = audioService.currentAudio
            .filter { $0.type == .narration && $0.sceneId == scene.id }
            .sorted { $0.createdAt > $1.createdAt }
        
        soundEffects = audioService.currentAudio
            .filter { $0.type == .soundEffect && $0.sceneId == scene.id }
            .sorted { $0.createdAt > $1.createdAt }
    }
    
    private func loadClips() {
        guard !isLoadingClips else { return }
        
        isLoadingClips = true
        let db = Firestore.firestore()
        
        db.collection("users")
            .document(story.userId)
            .collection("stories")
            .document(story.id)
            .collection("videos")
            .whereField("sceneId", isEqualTo: scene.id)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    Log.error(Log.video, error, "Error loading clips")
                    isLoadingClips = false
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    Log.p(Log.video, Log.read, "No clips found")
                    isLoadingClips = false
                    return
                }
                
                clips = documents.compactMap { doc -> Clip? in
                    let data = doc.data()
                    
                    guard let id = data["id"] as? String,
                          let sceneId = data["sceneId"] as? String,
                          let displayName = data["displayName"] as? String,
                          let status = data["status"] as? String else {
                        return nil
                    }
                    
                    return Clip(
                        id: id,
                        sceneId: sceneId,
                        displayName: displayName,
                        status: status,
                        aimlapiUrl: data["aimlapiUrl"] as? String,
                        mediaUrl: data["mediaUrl"] as? String,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    )
                }
                
                isLoadingClips = false
            }
    }
}

struct AssemblyCard: View {
    let assembly: Assembly
    @Binding var player: AVPlayer?
    @Binding var isPlayingPreview: Bool
    @State private var isSaving = false
    @State private var showPhotoPermissionAlert = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(assembly.displayName)
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Status: \(assembly.status)")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            if let url = assembly.mediaUrl,
               let videoURL = URL(string: url) {
                HStack(spacing: 16) {
                    Button {
                        // Create and configure player
                        player = AVPlayer(url: videoURL)
                        isPlayingPreview = true
                    } label: {
                        Label("Play Preview", systemImage: "play.circle.fill")
                            .foregroundColor(.blue)
                    }
                    .sheet(isPresented: $isPlayingPreview) {
                        VideoPlayer(player: player)
                            .onDisappear {
                                player?.pause()
                                player?.seek(to: .zero)
                            }
                    }
                    
                    if assembly.status == "completed" {
                        Button {
                            Task {
                                await checkPhotoPermissionAndSave(from: videoURL)
                            }
                        } label: {
                            Label(isSaving ? "Saving..." : "Save to Photos", 
                                  systemImage: "square.and.arrow.down")
                                .foregroundColor(.green)
                        }
                        .disabled(isSaving)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.2))
        .cornerRadius(10)
        .alert("Photos Permission Required", isPresented: $showPhotoPermissionAlert) {
            Button("Open Settings", role: .none) {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please allow access to Photos to save videos.")
        }
    }
    
    private func checkPhotoPermissionAndSave(from url: URL) async {
        Log.p(Log.video, Log.start, "Checking Photos permission for saving video")
        
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch status {
        case .notDetermined:
            let granted = await PHPhotoLibrary.requestAuthorization(for: .addOnly) == .authorized
            if granted {
                await saveToPhotos(from: url)
            } else {
                showPhotoPermissionAlert = true
            }
        case .restricted, .denied:
            Log.p(Log.video, Log.event, Log.error, "Photos access denied")
            showPhotoPermissionAlert = true
        case .authorized, .limited:
            await saveToPhotos(from: url)
        @unknown default:
            Log.p(Log.video, Log.event, Log.error, "Unknown Photos authorization status")
            showPhotoPermissionAlert = true
        }
    }
    
    private func saveToPhotos(from url: URL) async {
        Log.p(Log.video, Log.start, "Starting video save to Photos")
        isSaving = true
        
        do {
            // Create a unique temporary file URL
            let temporaryFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            
            Log.p(Log.video, Log.event, "Downloading to temporary file: \(temporaryFileURL.path)")
            
            // Download the video
            let (downloadedURL, response) = try await URLSession.shared.download(from: url)
            
            // Validate response
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                Log.p(Log.video, Log.event, Log.error, "Invalid response downloading video")
                isSaving = false
                return
            }
            
            // Move downloaded file to our temporary location
            try FileManager.default.moveItem(at: downloadedURL, to: temporaryFileURL)
            
            // Log file details
            let fileSize = try temporaryFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            Log.p(Log.video, Log.event, "Downloaded video size: \(fileSize) bytes")
            
            // Save to Photos
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: temporaryFileURL)
            }
            
            Log.p(Log.video, Log.save, "Video saved to Photos successfully")
            
            // Clean up
            try? FileManager.default.removeItem(at: temporaryFileURL)
            
        } catch let error as NSError {
            // Detailed error logging
            Log.p(Log.video, Log.event, Log.error, """
                Save failed:
                - Domain: \(error.domain)
                - Code: \(error.code)
                - Description: \(error.localizedDescription)
                - Underlying Error: \((error.userInfo[NSUnderlyingErrorKey] as? Error)?.localizedDescription ?? "None")
                """)
        }
        
        isSaving = false
    }
}

#Preview {
    AssemblerView(stories: [])
        .environmentObject(AuthenticationService.preview)
} 