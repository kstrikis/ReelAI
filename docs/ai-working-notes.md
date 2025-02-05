dependencies (visible in ReelAI.xcodeproj/project.pbxproj):
- FirebaseAnalytics
- FirebaseAuthCombine-Community (FirebaseAuthCombineSwift)
- FirebaseCore
- FirebaseCrashlytics
- FirebaseFirestoreCombine-Community (FirebaseFirestoreCombineSwift)
- FirebaseStorageCombine-Community (FirebaseStorageCombineSwift)

Recent Changes (2024-02-03):
1. Cleaned up repository:
   - Removed accidentally committed Xcode user data (xcuserdata)
   - Added proper .gitignore file to prevent future commits of user-specific files

2. Firebase Integration:
   - Added Firebase SDK dependencies through Swift Package Manager
   - Configured FirebaseApp initialization in ReelAIApp.swift
   - Added NavigationView wrapper for better navigation support

Known Issues:
- Build signing configuration needed (development team must be selected in Xcode)
- SwiftLint warnings present in ReelAIApp.swift and test files (line length violations)

Next Steps:
1. Configure code signing in Xcode
2. Address SwiftLint warnings
3. Set up proper Firebase configuration with GoogleService-Info.plist

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
Our schema revolves around a few key collections. We'll follow lowerCamelCase for fields and plural names for collections. This provides consistency in our Swift code and Firestore queries.

A. Users Collection ("users")
  – Each user document is keyed by the UID from Firebase Auth.
  – Fields (in lowerCamelCase):
   • displayName (String) – User's chosen display name.
   • email (String, optional) – Email from Auth (if available).
   • profileImageUrl (String, optional) – Link to user avatar stored in Firebase Storage.
   • createdAt (Timestamp) – When the user joined.
   • additional future fields (e.g., bio, socialLinks...) can be added as needed.

  // Sample document structure for a user:
  {
    "displayName": "Demo User",
    "email": "demo@example.com",
    "profileImageUrl": "gs://<bucket>/users/demoUser.png",
    "createdAt": <Timestamp>
  }

B. Videos Collection ("videos")
  – Each video document represents a full video created by a user and is stored in Firestore.
  – Fields:
   • videoId (String) – Unique identifier (could also use the document ID).
   • ownerId (String) – The UID of the user who created the video.
   • title (String) – Title or short description.
   • description (String, optional) – A fuller explanation.
   • mediaUrls (Map or Array) – Collection of URLs (from Firebase Storage) for the various video clips, AI-generated images, and processed audio files.
    – e.g., { "rawClip": "<url>", "editedClip": "<url>" } or an array of { "type": "rawClip", "url": "<url>" } items.
   • createdAt (Timestamp) – Timestamp of video creation.
   • updatedAt (Timestamp, optional) – For updates.
   • status (String) – e.g., "processing", "completed", "error".  
   • // Future: You can add fields for AI features (scriptGenerated, voiceVersion, etc.)

  // Example document for a video:
  {
    "ownerId": "UID_123456",
    "title": "Absurd Meme Creation",
    "description": "A hilariously absurd mashup of AI clips",
    "mediaUrls": {
        "rawClip": "gs://<bucket>/videos/video123/raw.mp4",
        "editedClip": "gs://<bucket>/videos/video123/edited.mp4"
    },
    "createdAt": <Timestamp>,
    "status": "completed"
  }

C. Interactions (Comments, Likes, Shares)
We can approach interactions in one of two ways. For an MVP, a simple method is to use subcollections under each video.

  – Under each video document, include:
   a. Subcollection "comments"
    • Fields:
     – commentId (String, optional – Firestore auto-ID works well)
     – authorId (String) – UID of commenting user.
     – text (String) – Comment content.
     – createdAt (Timestamp)

    // Example path: videos/{videoId}/comments/{commentId}
   
   b. Subcollection "likes"
    • Instead of storing detailed information, you might simply store a document for each like:
     – Fields:
      • userId (String) – Which user liked the video.
      • createdAt (Timestamp) – (Optional) when the like was made.
    // Alternatively, if likes are very common, you might store an array of userIds on the parent video document,
    // but that array pattern can have limitations as the like count scales.

   c. (Optional for MVP) Subcollection "shares" if you want to track this behavior.

──────────────────────────────────────────────
3. Firebase Storage Structure
──────────────────────────────────────────────
We'll use Firebase Storage to hold the actual media files referenced in our Firestore documents.

• Organization in Storage should be clear and maintainable:
  – /users/{uid}/profileImage.jpg  
  – /videos/{videoId}/raw.mp4  
  – /videos/{videoId}/edited.mp4  
  – Future additions, such as AI-generated images or audio clips, could fit under similar directories (e.g., /videos/{videoId}/aiImages/...).

──────────────────────────────────────────────
4. Naming Conventions in Swift & Firestore
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
5. Comments on Future Planning
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

~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# AI Working Notes

## Latest Updates
- Added new AI Tools tab with placeholder features:
  - Story Maker (coming soon)
  - Clip Maker (coming soon)
  - Audio Maker (coming soon)
  - Assembler (coming soon)
  - Publisher (functional)
- Implemented video publishing functionality:
  - Video selection from library
  - Title and description input
  - Upload progress tracking
  - Upload cancellation support
  - Success/error handling
- Modified tab structure:
  - Camera (leftmost)
  - AI Tools (center-left)
  - Home (center-right)
  - Menu (rightmost)
- Fixed camera orientation by setting videoRotationAngle to 90 degrees
- Camera improvements:
  - Using front camera by default
  - Added camera flip button
  - Proper camera lifecycle management with tab changes
  - Fixed video orientation issues
  - Added gallery access button
- Added video persistence and gallery:
  - Created LocalVideoService for persistent video storage in Documents directory
  - Implemented GalleryView with video thumbnails and playback
  - Modified video recording flow to save locally before upload
  - Videos now persist between app launches
  - Gallery accessible via button in camera view
- Remaining tasks:
  - Address SwiftLint warnings in CameraManager.swift
  - Add proper error handling for camera permissions
  - Add loading states for camera initialization
  - Add video deletion capability in gallery
  - Add video sharing from gallery
  - Implement video processing status indicators
  - Consider adding video metadata editing (title, description) in gallery

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