import SwiftUI

struct StoryMakerView: View {
    @EnvironmentObject var authService: AuthenticationService
    @StateObject private var storyService = StoryService()
    
    // UI State
    @State private var storyPrompt: String = ""
    @State private var isGenerating: Bool = false
    @State private var showingHistory: Bool = false
    @State private var errorMessage: String?
    @State private var showingError: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Story Input Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Create New Story")
                        .font(.title)
                        .foregroundColor(.white)
                    
                    TextEditor(text: $storyPrompt)
                        .frame(height: 120)
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                    
                    Button(action: generateStory) {
                        HStack {
                            Text(isGenerating ? "Generating..." : "Generate Story")
                            if isGenerating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(storyPrompt.isEmpty || isGenerating ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .disabled(storyPrompt.isEmpty || isGenerating)
                }
                .padding()
                .background(Color.black.opacity(0.2))
                .cornerRadius(12)
                
                // Current Story or History
                if let story = storyService.currentStory {
                    StoryView(story: story)
                } else if showingHistory {
                    PreviousStoriesView(stories: storyService.previousStories)
                }
                
                // Toggle between current and history
                if storyService.currentStory != nil || !storyService.previousStories.isEmpty {
                    Toggle("Show Story History", isOn: $showingHistory)
                        .foregroundColor(.white)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .spaceBackground()
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred")
        }
        .onAppear {
            loadUserStories()
        }
    }
    
    private func loadUserStories() {
        if case let .signedIn(user) = authService.authState {
            storyService.loadPreviousStories(for: user.uid)
        }
    }
    
    private func generateStory() {
        guard case let .signedIn(user) = authService.authState else {
            errorMessage = "Please sign in to create stories"
            showingError = true
            Log.error(Log.ai_story, StoryServiceError.noUserLoggedIn)
            return
        }
        
        guard !storyPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        
        isGenerating = true
        Log.p(Log.ai_story, Log.start, "Generating story for user: \(user.uid)")
        
        storyService.createStory(userId: user.uid, prompt: storyPrompt) { result in
            isGenerating = false
            
            switch result {
            case .success:
                storyPrompt = "" // Clear the prompt
                showingHistory = false // Show the new story
                Log.p(Log.ai_story, Log.event, Log.success, "Story generated successfully")
                
            case .failure(let error):
                errorMessage = error.localizedDescription
                showingError = true
                Log.error(Log.ai_story, error, "Failed to generate story")
            }
        }
    }
}

struct StoryView: View {
    let story: Story
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Story Title: \(story.title)")
                .font(.title2)
                .foregroundColor(.white)
            
            Text("Template: \(story.template)")
                .font(.headline)
                .foregroundColor(.white.opacity(0.8))
            
            ForEach(story.scenes) { scene in
                SceneView(scene: scene)
                    .padding(.bottom, 10)
            }
            
            if let jsonString = story.jsonRepresentation {
                DisclosureGroup("Debug Info") {
                    Text(jsonString)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .foregroundColor(.white)
                .padding(.top)
            }
        }
        .padding()
        .background(Color.black.opacity(0.2))
        .cornerRadius(12)
    }
}

struct PreviousStoriesView: View {
    let stories: [Story]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Previous Stories")
                .font(.title2)
                .foregroundColor(.white)
            
            if stories.isEmpty {
                Text("No previous stories found")
                    .foregroundColor(.white.opacity(0.7))
                    .padding()
            } else {
                ForEach(stories) { story in
                    StoryView(story: story)
                }
            }
        }
    }
}

struct SceneView: View {
    let scene: StoryScene

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scene \(scene.sceneNumber)")
                .font(.headline)
                .foregroundColor(.white)

            if let narration = scene.narration {
                Text("Narration: \(narration)")
                    .foregroundColor(.white.opacity(0.9))
            }
            if let voice = scene.voice {
                Text("Voice: \(voice)")
                    .foregroundColor(.white.opacity(0.9))
            }
            Text("Visual Prompt: \(scene.visualPrompt)")
                .foregroundColor(.white.opacity(0.9))
            if let audioPrompt = scene.audioPrompt {
                Text("Audio Prompt: \(audioPrompt)")
                    .foregroundColor(.white.opacity(0.9))
            }
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    StoryMakerView()
        .environmentObject(AuthenticationService.preview)
} 