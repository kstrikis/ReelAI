dependencies (visible in ReelAI.xcodeproj/project.pbxproj):
- FirebaseAnalytics
- FirebaseAuthCombine-Community (FirebaseAuthCombineSwift)
- FirebaseCore
- FirebaseCrashlytics
- FirebaseFirestoreCombine-Community (FirebaseFirestoreCombineSwift)

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
- Cleaned up ContentView.swift:
  - Removed redundant outer ZStack
  - Fixed sheet modifier placement
  - Removed unused signOut function
  - Simplified view hierarchy and modifiers
- Fixed error handling in LoginView.swift:
  - Removed redundant AuthError type casting
  - Simplified error message display
- Fixed AppLogger.ui references and added SwiftLint exception
- Remaining tasks:
  - Address force cast in LoginView.swift
  - Fix multiple closures with trailing closure violations
  - Resolve TODOs in SideMenuView.swift
  - Add proper trailing newlines to files

## Configuration Notes
- Using SwiftUI for UI components
- Firebase for authentication and data storage
- SwiftLint for code quality enforcement

## Debugging Notes
- NavigationView and toolbar styling requires careful modifier ordering
- Error handling should be simplified where possible
- View hierarchy should be kept minimal for better performance

## Decisions
- Keeping AppLogger.ui as short name with SwiftLint exception
- Simplified error handling in authentication flows
- Removed redundant view wrapping in ContentView