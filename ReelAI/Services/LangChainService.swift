import Foundation
import Combine
import FirebaseFunctions

/// Service to handle story generation through Firebase Cloud Functions
final class LangChainService {
    static let shared = LangChainService()
    private let functions: Functions
    
    private init() {
        #if DEBUG
        // Use local emulator in debug builds if available
        self.functions = Functions.functions()
        if ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATOR"] == "1" {
            functions.useEmulator(withHost: "localhost", port: 5001)
        }
        #else
        self.functions = Functions.functions()
        #endif
        
        Log.p(Log.ai_story, Log.start, "LangChain service initialized with Firebase Functions")
    }
    
    /// Generates a story using Firebase Cloud Function
    /// - Parameter prompt: User's story prompt
    /// - Returns: Generated Story
    func generateStory(from prompt: String) async throws -> Story {
        Log.p(Log.ai_story, Log.generate, "Requesting story generation via Cloud Function")
        
        do {
            // Call the Firebase Cloud Function
            let result = try await functions
                .httpsCallable("generateStory")
                .call(["prompt": prompt])
            
            // Parse the response
            guard let data = result.data as? [String: Any] else {
                throw LangChainError.parsingError("Invalid response format")
            }
            
            // Convert to JSON data for decoding
            let jsonData = try JSONSerialization.data(withJSONObject: data)
            let story = try JSONDecoder().decode(Story.self, from: jsonData)
            
            Log.p(Log.ai_story, Log.generate, Log.success, "Story generated successfully")
            return story
            
        } catch let error as NSError {
            switch error.domain {
            case FunctionsErrorDomain:
                switch FunctionsErrorCode(rawValue: error.code) {
                case .notFound:
                    Log.error(Log.ai_story, LangChainError.functionNotFound)
                    throw LangChainError.functionNotFound
                case .unauthenticated:
                    Log.error(Log.ai_story, LangChainError.unauthorized)
                    throw LangChainError.unauthorized
                case .resourceExhausted:
                    Log.error(Log.ai_story, LangChainError.rateLimited)
                    throw LangChainError.rateLimited
                default:
                    let message = error.localizedDescription
                    Log.error(Log.ai_story, LangChainError.apiError(message))
                    throw LangChainError.apiError(message)
                }
            default:
                Log.error(Log.ai_story, error)
                throw error
            }
        }
    }
}

// MARK: - Error Types

enum LangChainError: Error, LocalizedError {
    case functionNotFound
    case unauthorized
    case rateLimited
    case apiError(String)
    case parsingError(String)
    
    var errorDescription: String? {
        switch self {
        case .functionNotFound:
            return "Story generation function not found"
        case .unauthorized:
            return "Unauthorized. Please sign in again."
        case .rateLimited:
            return "Too many requests. Please try again later."
        case .apiError(let message):
            return "API Error: \(message)"
        case .parsingError(let message):
            return "Failed to parse response: \(message)"
        }
    }
} 