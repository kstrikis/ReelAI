dependencies (visible in ReelAI.xcodeproj/project.pbxproj):
- FirebaseAnalytics
- FirebaseAuthCombine-Community (FirebaseAuthCombineSwift)
- FirebaseCore
- FirebaseCrashlytics
- FirebaseFirestoreCombine-Community (FirebaseFirestoreCombineSwift)
- FirebaseStorageCombine-Community (FirebaseStorageCombineSwift)
- FirebaseFunctions-Community (FirebaseFunctionsSwift)

Recent Changes (2024-02-03):
1. Cleaned up repository:
   - Removed accidentally committed Xcode user data (xcuserdata)
   - Added proper .gitignore file to prevent future commits of user-specific files

2. Firebase Integration:
   - Added Firebase SDK dependencies through Swift Package Manager
   - Configured FirebaseApp initialization in ReelAIApp.swift
   - Added NavigationView wrapper for better navigation support

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Below is an end-to-end plan for our MVP's data architecture in Firebase, along with naming conventions and inline comments for future enhancements.

──────────────────────────────────────────────
1. Firebase Authentication & Demo Mode
──────────────────────────────────────────────
• We'll use Firebase Auth for standard user authentication.  
• For demo purposes, add a "Demo Login" button on the login screen.  
  – When tapping Demo Login, use a fixed demo account (for example, hard-code credentials or use Firebase's anonymous authentication and then link to a "demo" profile).  
  – This lets developers and demonstrators bypass a full sign-up flow quickly.  

──────────────────────────────────────────────
2. Firestore Data Model
──────────────────────────────────────────────
Our schema revolves around a few key collections. We'll follow lowerCamelCase for fields and plural names for collections.

A. Users Collection ("users")
  – Each user document is keyed by the UID from Firebase Auth.
  – Fields (in lowerCamelCase):
   • displayName (String) – User's chosen display name.
   • username (String) – Unique username for the user.
   • email (String, optional) – Email from Auth (if available).
   • profileImageUrl (String, optional) – Link to user avatar stored in Firebase Storage.
   • createdAt (Timestamp) – When the user joined.

B. Videos Collection ("videos")
  – Each video document represents a user-uploaded video.
  – Core Fields:
   • ownerId (String) – The UID of the user who created the video
   • username (String) – Creator's username (denormalized for efficiency)
   • title (String) – Video title
   • description (String, optional) – Full description
   • computedMediaUrl (String) – Computed URL to the video file in Storage, derived from video ID and owner ID
   • createdAt (Timestamp) – Creation time
   • updatedAt (Timestamp) – Last modification time
  – Engagement Sub-object:
   • viewCount (Int) – Number of views
   • likeCount (Int) – Number of likes
   • dislikeCount (Int) – Number of dislikes
   • tags (Map<String, Int>) – Tag name to usage count mapping

  // Example document structure:
  {
    "ownerId": "user123",
    "username": "creator",
    "title": "My Cool Video",
    "description": "Check this out!",
    "computedMediaUrl": "// mediaUrl is now computed from video ID and owner ID",
    "createdAt": <Timestamp>,
    "updatedAt": <Timestamp>,
    "engagement": {
      "viewCount": 1000,
      "likeCount": 50,
      "dislikeCount": 2,
      "tags": {
        "funny": 30,
        "creative": 25
      }
    }
  }

C. Comments Structure
Comments are stored as subcollections under each video document:
videos/{videoId}/comments/{commentId}

  – Comment Fields:
   • userId (String) – Commenter's UID
   • username (String) – Commenter's username
   • text (String) – Comment content
   • createdAt (Timestamp) – When posted
   • likeCount (Int) – Number of likes
   • dislikeCount (Int) – Number of dislikes
   • replyTo (String, optional) – Parent comment ID if this is a reply

  // Example comment document:
  {
    "userId": "user456",
    "username": "commenter",
    "text": "Great video!",
    "createdAt": <Timestamp>,
    "likeCount": 5,
    "dislikeCount": 0,
    "replyTo": null
  }

D. Reactions Tracking
Reactions are stored in subcollections to track individual user reactions:
videos/{videoId}/comments/{commentId}/reactions/{reactionId}

  – Reaction Fields:
   • userId (String) – User who reacted
   • createdAt (Timestamp) – When the reaction was made
   • isLike (Boolean) – true for like, false for dislike

  // Example reaction document:
  {
    "userId": "user789",
    "createdAt": <Timestamp>,
    "isLike": true
  }

──────────────────────────────────────────────
3. Key Operations
──────────────────────────────────────────────

A. Video Operations:
  • Create video with initial metadata
  • Fetch videos (with optional user filter)
  • Update video metadata
  • Delete video (and all associated subcollections)

B. Engagement Operations:
  • Increment view count
  • Add/remove likes or dislikes
  • Add tags with user counts
  • Track user-specific reactions

C. Comment Operations:
  • Add comment (top-level or reply)
  • Fetch comments for a video
  • Add/remove comment reactions
  • Track user-specific reactions to comments

D. Query Patterns:
  • Get recent videos
  • Get user's videos
  • Get video comments
  • Check user's reactions
  • Get trending videos (by engagement)

──────────────────────────────────────────────
4. Security Rules
──────────────────────────────────────────────
Key security considerations:
• Users can only edit their own profiles
• Anyone can view videos and comments
• Only authenticated users can create content
• Users can only edit/delete their own content
• Reaction counts must be incremented/decremented atomically
• One reaction per user per content item

──────────────────────────────────────────────
5. Firebase Storage Structure
──────────────────────────────────────────────
We'll use Firebase Storage to hold the actual media files referenced in our Firestore documents.

• Organization in Storage should be clear and maintainable:
  – /users/{uid}/profileImage.jpg
  – /videos/{userId}/{videoId}.mp4
  – Future additions, such as AI-generated content, should follow the user-based structure:
    • /videos/{userId}/ai/{videoId}/audio.mp3
    • /videos/{userId}/ai/{videoId}/images/...

• Key points about video storage:
  – Videos are organized by user ID first, then video ID
  – This structure allows for easy user-based queries and cleanup
  – Each video has a unique ID that's shared between Firestore and Storage
  – The computed URL in the Video model matches this structure

──────────────────────────────────────────────
6. Naming Conventions in Swift & Firestore
──────────────────────────────────────────────
• Collections: Use plural names, e.g., "users", "videos", "comments", "likes".  
• Document Fields: Use lowerCamelCase (e.g., ownerId, createdAt, profileImageUrl).  
• Swift Models: Mirror Firestore fields with Swift structs/classes that conform to Codable. For example:

  struct User: Codable {
   let displayName: String
   let email: String?
   let profileImageUrl: String?
   let createdAt: Date
  }

  struct Video: Codable {
   let ownerId: String
   let title: String
   let description: String?
   let mediaUrls: [String: String]  // e.g., a dictionary mapping clip types to URLs
   let createdAt: Date
   let status: String
  }

• By following a consistent naming scheme, both the Firestore documents and the Swift code remain in sync, simplifying queries and data parsing.

──────────────────────────────────────────────
7. Comments on Future Planning
──────────────────────────────────────────────
• For now, our plan focuses on core functionality: user authentication (including a demo mode), video capture/upload, basic editing metadata storage, and simple interaction tracking.  
• As we evolve the app, we can introduce additional fields like AI-generated script data, voice synthesis metadata, and more refined editing history.  
• We're mindful of avoiding over-embedding data; by favoring references (like storing user UID in video documents) and subcollections for interactions, we maintain scalability.
  – If we see extremely heavy interaction volumes, we might consider alternative patterns (like storing aggregate counts or using Cloud Functions for real-time tallies).

──────────────────────────────────────────────
Summary
──────────────────────────────────────────────
By using Firebase Auth, Firestore, and Firebase Storage together, we'll create a fast, scalable MVP that lets users log in (with a demo option), create videos from various media components, and interact with content in real time. Our data model uses clean naming conventions and a modular structure that is easy to extend as more advanced AI features are added.

This approach meets our immediate need to demonstrate a meme video creation tool while laying the groundwork for future enhancements.

──────────────────────────────────────────────
6. Video Publishing Flow
──────────────────────────────────────────────
The video publishing process follows these steps:

1. Video Selection & Processing:
   – User selects video through PhotosPicker
   – System creates a temporary file in app's sandbox
   – Video is loaded through Photos framework for preview
   – A unique videoId is generated for both Storage and Firestore

2. Upload Process:
   – VideoUploadService verifies file stability with retries
   – Uploads to Firebase Storage at /videos/{userId}/{videoId}.mp4
   – Progress updates are provided through Combine publishers
   – Metadata includes content type and file size

3. State Management:
   – PublishingView tracks upload state and progress
   – Provides user feedback through progress updates
   – Handles errors and success states
   – Cleans up temporary files after upload

4. Key Implementation Notes:
   – Uses Swift's PhotosPicker for video selection
   – Implements retry logic for file size verification
   – Provides progress updates through Combine
   – Handles cleanup of temporary files
   – Maintains consistent videoId between Storage and Firestore

──────────────────────────────────────────────
7. Firebase Data Audit Tool
──────────────────────────────────────────────
A debug tool has been implemented to maintain data integrity across Firebase services.

• Audit Checks:
  – Firestore video documents without Storage files
  – Invalid video documents (decode failures, missing users)
  – Storage files without Firestore documents
  – Files not following .mp4 format
  – Orphaned reactions
  – Path structure violations

• Tool Features:
  – One-click audit initiation
  – Progress tracking during audit
  – Detailed issue descriptions
  – Safe deletion of problematic items
  – Comprehensive logging
  – Results clearing

• Implementation Notes:
  – Located in DebugMenuView for development builds only
  – Uses async/await for efficient Firebase operations
  – Maintains atomic operations for deletions
  – Provides clear error messages and paths
  – Follows established logging standards

• Usage Guidelines:
  – Run periodically to catch data inconsistencies
  – Review issues before deletion
  – Check logs for operation details
  – Clear results after review
  – Use during development and testing phases

──────────────────────────────────────────────
8. Firebase Function Testing
──────────────────────────────────────────────
A. Story Generation Function
To test the story generation function locally using Firebase emulators:

1. Start the emulators:
   ```bash
   cd functions
   npm run serve
   ```

2. Get a test auth token:
   ```bash
   curl http://127.0.0.1:5001/reelai-53f8b/us-central1/getTestToken
   ```

3. Call the generateStory function:
   ```bash
   curl -X POST \
     -H "Content-Type: application/json" \
     -H "Authorization: Bearer YOUR_TEST_TOKEN" \
     -d '{"data":{"prompt":"Your story prompt here"}}' \
     http://127.0.0.1:5001/reelai-53f8b/us-central1/generateStory
   ```

Response Format:
```json
{
  "result": {
    "success": true,
    "result": {
      "id": "story_timestamp",
      "title": "Generated Story Title",
      "template": "Original Prompt",
      "backgroundMusicPrompt": "Story-wide background music description",
      "scenes": [
        {
          "id": "scene1",
          "sceneNumber": 1,
          "narration": "Scene narration text",
          "voice": "ElevenLabs Voice ID",
          "visualPrompt": "Detailed visual description",
          "audioPrompt": "Scene-specific sound effects",
          "duration": 5
        }
        // ... more scenes
      ]
    }
  }
}
```

Key Points:
- The function requires authentication (even in emulator)
- Each story has both a story-wide background music prompt and scene-specific audio prompts
- Scene durations are between 3-10 seconds
- The AI generates 3-5 scenes per story
- Visual prompts include camera angles and lighting details
- Audio prompts are specific to each scene's action

Common Testing Prompts:
1. "A funny story about a cat learning to code"
2. "An inspiring tale of a small robot finding its purpose"
3. "A magical journey through a child's art coming to life"

These prompts are good for testing as they exercise different aspects of the generation (humor, emotion, visual creativity).

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# AI Working Notes

## Latest Updates (2024-02-07)
- Implemented basic Story Maker functionality:
  - Created `Story` and `Scene` models for representing story data.
  - Created `StoryService` to handle story generation (currently with mock data).
  - Created `StoryMakerView` to display the generated story.
  - Integrated `StoryMakerView` into `AIToolsView`.
  - Added basic Firestore integration for saving stories.
  - Added JSON representation to the `Story` model.
  - Added comprehensive logging.

## Configuration Notes
- Story data is stored in a "stories" subcollection under each user in Firestore.

## Debugging Notes
- Currently using mock data for story generation. AI integration is the next step.
- JSON representation is displayed in the UI for debugging purposes.

## Decisions
- Using `StateObject` for `StoryService` to ensure proper lifecycle management.
- Storing stories in Firestore for persistence.
- Generating JSON representation for easy integration with other AI tools.

## Logging Standards
- Using 📝 for Firestore-related logs.
- Using 🤖 for AI-related logs.

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# AI Working Notes

## Latest Updates (2024-02-14)
- Fixed story generation parsing issues:
  - Changed Story and StoryScene models to use String IDs instead of UUIDs to match Firebase function output
  - Added custom ISO8601 date parsing strategy to handle timestamps with fractional seconds
  - Added detailed error logging for JSON parsing failures
  - Improved error messages for debugging decoding issues

## Story Generation Notes
1. ID Formats:
   - Story IDs: `story_${timestamp}` format (e.g., "story_1739565107202")
   - Scene IDs: `scene${number}` format (e.g., "scene1", "scene2")
   - These formats are standardized between the Firebase function and iOS app

2. Date Handling:
   - Timestamps are in ISO8601 format with fractional seconds
   - Example: "2025-02-14T20:44:25.265Z"
   - Custom decoder handles both with and without fractional seconds

3. Response Format:
```json
{
  "success": true,
  "result": {
    "id": "story_timestamp",
    "title": "Story Title",
    "template": "default",
    "backgroundMusicPrompt": "Music description...",
    "scenes": [
      {
        "id": "scene1",
        "sceneNumber": 1,
        "narration": "Scene narration...",
        "voice": "ElevenLabs Adam",
        "visualPrompt": "Visual description...",
        "audioPrompt": "Audio effects...",
        "duration": 5
      }
    ],
    "createdAt": "ISO8601 timestamp",
    "userId": "Firebase Auth UID"
  }
}
```

4. Known Limitations:
   - Scene IDs from the AI might come without underscores (e.g., "scene1" instead of "scene_1")
   - Background music prompt is required in the response
   - Scene duration must be between 3-10 seconds

## Configuration Notes
- Using SwiftUI for UI components
- Firebase for authentication and data storage
- SwiftLint for code quality enforcement
- Camera restricted to portrait mode only
- Videos stored in Documents/Videos directory for persistence

## Debugging Notes
- Camera orientation needs to be set to 90 degrees for proper portrait display
- Camera initialization should happen when view becomes active
- Camera cleanup on view disappear is important for resource management
- Videos are now saved locally before upload to ensure persistence
- Thumbnails are generated on-demand for better performance
- Gallery view is presented modally to maintain camera state

## Decisions
- Using singleton pattern for CameraManager to prevent multiple instances
- Keeping camera in portrait mode only
- Front camera as default for better user experience
- Tab-based navigation with proper view lifecycle management
- Storing videos in Documents directory for persistence and backup
- Using AVAssetImageGenerator for thumbnail generation
- Gallery accessed via camera view to maintain better UX flow

## Logging Standards
- Each component uses a consistent first emoji as its "sheet" identifier:
  - 📼 for LocalVideoService operations
  - 🖼️ for Gallery/UI operations
  - 📸 for Camera operations
  - 📤 for Upload operations
  - 🔄 for async/await conversions

- Second emoji indicates specific operation type:
  - 🎬 for initialization/setup
  - 📁 for directory/file operations
  - 💾 for saving operations
  - 🔍 for search/fetch operations
  - 🗑️ for deletion operations
  - 🖼️ for thumbnail operations
  - ⚙️ for configuration
  - 📊 for progress/status
  - ✅ for success
  - 🔑 for authentication
  - 📤 for upload operations
  - 🛑 for stopping/cleanup

- Error logging uses distinct patterns:
  - ❌ 💥 for serious errors
  - ❌ 🔒 for authentication errors
  - ❌ 🚫 for validation/state errors
  - ⚠️ for warnings

Example:
```swift
print("📼 🎬 Initializing LocalVideoService")  // Component + Operation
print("❌ 💥 Failed to save video: \(error)")   // Error pattern
```

7. Video Feed Implementation Notes (2024-02-06)
──────────────────────────────────────────────
Current Concerns:

1. Resource Loading:
   - Duplicate resource fetching warnings (GTMSessionFetcher) were initially observed but are no longer present. URL caching is confirmed to be working correctly via added log statements. The previous warnings were likely transient or related to external factors. We will continue to monitor Firebase Storage usage.

2. Video Transform Issues:
    - `AVAssetTrack` warnings about unrecognized "currentVideoTrack.preferredTransform" keys were persistently observed, despite multiple attempts to load `preferredTransform` correctly on the `AVAsset` and avoid any direct access on `AVAssetTrack`. A project-wide search for "currentVideoTrack" yielded no results, suggesting the issue originates from within Apple's frameworks. Given the time constraints and the likelihood that the warning is benign, this issue is marked as **WON'T FIX** for now. We will continue to monitor for any negative side effects.

Progress:
- Successfully implemented single player initialization per video
- Achieved stable video looping
- Eliminated multiple buffering states
- Implemented clean preloading sequence
- Reduced memory footprint by limiting preloaded videos

Next Steps:
1. Remove redundant preloadVideosAround() calls
2. Research and implement correct AVAssetTrack transform loading
3. Verify resource cleanup on video transitions

## [Date] - Prioritize Player Preparation

**Problem:** Even with the `@StateObject` fix, there was still a small chance of encountering a black screen if the user swiped very quickly to a video whose player hadn't been prepared yet.

**Solution:** Modified the `handleIndexChange` function to prioritize player preparation based on proximity to the current index.  The code now sorts the indices within the preload window by their distance from the current index and prepares players in that order. This ensures that players for videos closer to the current view are prepared first, significantly reducing the likelihood of encountering an unprepared player.

**Configuration Changes:** None.

## [Date] - Fix Load More Videos Logic

**Problem:** The "load more videos" functionality was not triggering correctly. The `handleIndexChange` function was checking `videos.count` *before* the `videos` array was populated by the initial `loadVideos`