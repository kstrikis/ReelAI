import Foundation
import FirebaseFirestore
import FirebaseFirestoreCombineSwift
import Combine

class StoryService: ObservableObject {
    @Published var currentStory: Story?
    @Published var previousStories: [Story] = []
    private var cancellables = Set<AnyCancellable>()
    private let db = Firestore.firestore()
    private let langChain = LangChainService.shared
    
    init() {
        Log.p(Log.ai_story, Log.start, "Initializing StoryService")
    }
    
    // Placeholder templates. We'll expand these.
    private let templates: [String] = [
        "scary story. try not to get scared.",
        "an evil sorcerer was seen sucking out the intelligence and wisdom of a cat"
    ]
    
    func createStory(userId: String, prompt: String, completion: @escaping (Result<Void, StoryServiceError>) -> Void) {
        // Log the start of story creation
        Log.p(Log.ai_story, Log.generate, "Creating story with prompt: \(prompt)")
        
        Task {
            do {
                // Generate story using LangChain
                let newStory = try await langChain.generateStory(from: prompt)
                
                // Save to Firestore
                try await saveStoryToFirestore(newStory) { [weak self] result in
                    switch result {
                    case .success:
                        // Update local state after successful save
                        DispatchQueue.main.async {
                            self?.currentStory = newStory
                            if let story = self?.currentStory {
                                self?.previousStories.insert(story, at: 0)
                            }
                            completion(.success(()))
                        }
                        Log.p(Log.ai_story, Log.generate, Log.success, "Story created and saved: \(newStory.title)")
                        
                    case .failure(let error):
                        Log.error(Log.ai_story, error, "Failed to save story")
                        completion(.failure(error))
                    }
                }
            } catch let error as LangChainError {
                Log.error(Log.ai_story, error, "LangChain story generation failed")
                completion(.failure(.aiGenerationError(error)))
            } catch {
                Log.error(Log.ai_story, error, "Unexpected error during story creation")
                completion(.failure(.unexpectedError(error)))
            }
        }
    }
    
    func loadPreviousStories(for userId: String) {
        Log.p(Log.ai_story, Log.read, "Loading previous stories for user: \(userId)")
        
        db.collection("users").document(userId).collection("stories")
            .order(by: "createdAt", descending: true)
            .limit(to: 10) // Reasonable limit for now
            .snapshotPublisher()
            .map { snapshot -> [Story] in
                snapshot.documents.compactMap { document in
                    try? document.data(as: Story.self)
                }
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                if case let .failure(error) = completion {
                    Log.error(Log.ai_story, error, "Failed to load previous stories")
                }
            } receiveValue: { [weak self] stories in
                self?.previousStories = stories
                Log.p(Log.ai_story, Log.read, Log.success, "Loaded \(stories.count) previous stories")
            }
            .store(in: &cancellables)
    }

    // Generates a mock story for now.
    private func generateMockStory(userId: String, prompt: String) -> Story {
        let storyId = UUID()
        let scenes = [
            StoryScene(id: UUID(), 
                  sceneNumber: 1, 
                  narration: "Based on prompt: \(prompt)\nOnce upon a time...", 
                  voice: "ElevenLabs Adam", 
                  visualPrompt: "A dark forest", 
                  audioPrompt: "Spooky wind",
                  duration: 5.0),
            StoryScene(id: UUID(), 
                  sceneNumber: 2, 
                  narration: "There was a scary monster!", 
                  voice: "ElevenLabs Adam", 
                  visualPrompt: "A close-up of a monster's face", 
                  audioPrompt: "Monster roar",
                  duration: 7.0),
            StoryScene(id: UUID(), 
                  sceneNumber: 3, 
                  narration: "The end.", 
                  voice: "ElevenLabs Adam", 
                  visualPrompt: "A peaceful village", 
                  audioPrompt: "Birds chirping",
                  duration: 3.0)
        ]

        return Story(id: storyId, 
                    title: "Story: \(prompt.prefix(30))...", 
                    template: prompt, 
                    scenes: scenes, 
                    createdAt: Date(), 
                    userId: userId)
    }
    
    private func saveStoryToFirestore(_ story: Story, completion: @escaping (Result<Void, StoryServiceError>) -> Void) {
        let userStoriesCollection = db.collection("users").document(story.userId).collection("stories")

        do {
            try userStoriesCollection.document(story.id.uuidString).setData(from: story) { error in
                if let error = error {
                    Log.error(Log.firebase, error, "Failed to save story to Firestore")
                    completion(.failure(.firestoreError(error)))
                    return
                }
                Log.p(Log.firebase, Log.save, Log.success, "Story saved to Firestore: \(story.id)")
                completion(.success(()))
            }
        } catch {
            Log.error(Log.firebase, error, "Failed to encode story for Firestore")
            completion(.failure(.encodingError))
        }
    }
}

// Error types
enum StoryServiceError: Error, LocalizedError {
    case encodingError
    case firestoreError(Error)
    case noUserLoggedIn
    case aiGenerationError(Error)
    case unexpectedError(Error)
    
    var errorDescription: String? {
        switch self {
        case .encodingError:
            return "Failed to encode story data"
        case .firestoreError(let error):
            return "Firestore error: \(error.localizedDescription)"
        case .noUserLoggedIn:
            return "No user is currently logged in"
        case .aiGenerationError(let error):
            return "AI Generation error: \(error.localizedDescription)"
        case .unexpectedError(let error):
            return "Unexpected error: \(error.localizedDescription)"
        }
    }
} 