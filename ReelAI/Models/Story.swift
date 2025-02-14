import Foundation

// Represents the entire story generated by the AI.
struct Story: Codable, Identifiable {
    let id: UUID  // Unique identifier for the story
    let title: String // Title of the story
    let template: String // The template used (e.g., "scary story", "evil sorcerer")
    let backgroundMusicPrompt: String? // Story-wide background music prompt
    let scenes: [StoryScene] // Array of scenes composing the story
    let createdAt: Date // Timestamp for when the story was created
    let userId: String // ID of the user who created the story

    // Computed property to generate the JSON representation of the story.
    var jsonRepresentation: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys] // For readability
        do {
            let jsonData = try encoder.encode(self)
            return String(data: jsonData, encoding: .utf8)
        } catch {
            Log.p(Log.ai_story, Log.process, Log.error, "Could not encode Story to JSON: \(error)")
            return nil
        }
    }
}

// Represents a single scene within a story.
struct StoryScene: Codable, Identifiable {
    let id: UUID // Unique identifier for the scene
    let sceneNumber: Int // Order of the scene in the story
    let narration: String? // Text for the narration of this scene
    let voice: String? // The AI voice to use (e.g., "ElevenLabs Adam", "TikTok Voice 4")
    let visualPrompt: String // Prompt for the video/image generation (the "storyboard" part)
    let audioPrompt: String? // Prompt for background music or sound effects (optional)
    let duration: Double? // Estimated duration of the scene in seconds (optional, for later use)
} 