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
   • mediaUrl (String) – URL to the video file in Storage
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
    "mediaUrl": "gs://bucket/videos/video123.mp4",
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
  – /videos/{videoId}/raw.mp4  
  – /videos/{videoId}/edited.mp4  
  – Future additions, such as AI-generated images or audio clips, could fit under similar directories (e.g., /videos/{videoId}/aiImages/...).

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
- Standardized Firestore logging:
  - All database operations must use dedicated logging functions (dbEntry, dbSuccess, etc.)
  - Each log must include collection context
  - Removed generic methodEntry/Exit usage for database operations
  - Added comprehensive logging for all Firestore operations in FirestoreService
- Implemented comprehensive logging system:
  - Strategic logging at critical points:
    - State transitions (view lifecycle, user sessions, data models)
    - Asynchronous operation lifecycles
    - External service interactions
    - Resource management (allocation and cleanup)
    - Critical user actions
  - Breadcrumb trail approach for complex operations
  - Context preservation for debugging under time pressure
  - Recovery information in error logs
  - Performance and memory monitoring
  - Consistent formatting with component and operation identifiers
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