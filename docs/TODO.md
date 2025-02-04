```markdown
# ReelAI iOS Development Checklist

### **Phase 1: Firebase Auth & Session Management**  
**Objective**: Secure user auth flow for creators.  
- [ ] **1.1** – Initialize Firebase in `AppDelegate`/`@main` struct using `FirebaseApp.configure()`.  
- [ ] **1.2** – Implement email/password auth with SwiftUI:  
  ```swift  
  // AuthService.swift  
  func signUp(email: String, password: String) async throws -> AuthDataResult {  
    try await Auth.auth().createUser(withEmail: email, password: password)  
  }  
  ```  
- [ ] **1.3** – Add Google OAuth using `GIDSignIn` SDK (handle `GIDSignInDelegate` callbacks).  
- [ ] **1.4** – Create `UserSession` class (ObservableObject) to track auth state via `Auth.auth().addStateDidChangeListener`.  
- [ ] **1.5** – Write Firestore security rules to restrict user document writes to `request.auth.uid == resource.data.userId`.  

---

### **Phase 2: Video Upload & Firebase Storage Pipeline**  
**Objective**: End-to-end video upload, processing, and Firestore metadata sync.  
- [ ] **2.1** – Create `VideoUploadService` class with methods:  
  ```swift  
  func uploadVideo(_ url: URL, userId: String) async throws -> StorageReference {  
    let ref = Storage.storage().reference().child("videos/\(userId)/raw/\(UUID().uuidString).mp4")  
    let _ = try await ref.putFileAsync(from: url, metadata: nil)  
    return ref  
  }  
  ```  
- [ ] **2.2** – Write Cloud Function (TypeScript) to trigger OpenShot processing on `onFinalize`:  
  ```typescript  
  exports.processVideo = functions.storage.object().onFinalize(async (object) => {  
    if (object.name?.includes('/raw/')) {  
      // Call OpenShot AWS API here, save processed URL to Firestore  
    }  
  });  
  ```  
- [ ] **2.3** – Add Firestore `videos` collection schema:  
  ```swift  
  struct Video: Codable {  
    @DocumentID var id: String?  
    let userId: String  
    let title: String  
    let muscleGroup: String // Week 1 niche: Fitness Creator  
    let difficulty: Int  
    @ServerTimestamp var createdAt: Date?  
    let processedURL: String  
  }  
  ```  

---

### **Phase 3: Feed & UI Components**  
**Objective**: Build creator upload flow and consumer feed.  
- [ ] **3.1** – Create SwiftUI `VideoUploadView` with:  
  - Camera access via `AVCaptureSession`.  
  - Muscle group picker (hardcoded: "Chest", "Legs", etc.).  
  - Difficulty slider (1-5).  
- [ ] **3.2** – Implement infinite-scroll `VideoFeedView` using Firestore pagination:  
  ```swift  
  @FirestoreQuery(  
    collectionPath: "videos",  
    predicates: [.order(by: "createdAt", descending: true)]  
  ) private var videos: [Video]  
  ```  
- [ ] **3.3** – Integrate `AVPlayerViewController` for playback with custom controls (like, comment buttons).  

---

### **Phase 4: Prep for AI (Week 2)**  
**Objective**: Scaffold AI hooks without implementation.  
- [ ] **4.1** – Add `isAIProcessed` flag to `Video` Firestore schema.  
- [ ] **4.2** – Create placeholder `AIService` class with stubs:  
  ```swift  
  class AIService {  
    func generateCaption(for video: Video) async throws -> String { /* TBD */ }  
  }  
  ```  
- [ ] **4.3** – Reserve Firebase Storage path `videos/{userId}/ai_processed/` for future AI outputs.  

---

### **Phase 5: Testing & Deployment**  
**Objective**: Validate core flow and deploy.  
- [ ] **5.1** – Write snapshot tests for critical views (Xcode `XCTest`).  
- [ ] **5.2** – Configure Firebase App Distribution for TestFlight-like beta testing.  
- [ ] **5.3** – Set up GitHub Actions workflow for iOS build on `main` branch pushes.  

---

### **AI Future Tasks (Week 2 Placeholders)**  
- [ ] **W2.1** – Integrate Vertex AI for script generation (hook to `AIService`).  
- [ ] **W2.2** – Add ElevenLabs API for voice synthesis.  
- [ ] **W2.3** – Implement Stability AI/OpenShot template stitching.  

---

### **Usage Instructions**  
1. **Start at the first empty checkbox** (e.g., `Phase 0.1`).  
2. Run `CMD+F "[ ]"` to jump to the next incomplete task.  
3. After completing a task, replace `[ ]` with `[x]`.  
4. For code-heavy tasks, reference the embedded snippets.  
```