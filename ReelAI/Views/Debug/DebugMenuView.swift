#if DEBUG
import SwiftUI
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth

struct DebugMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showVideoList = false
    @State private var showVideoFeed = false
    @StateObject private var viewModel = DebugViewModel()
    
    var body: some View {
        List {
            Section("Video Tools") {
                Button(action: {
                    Log.p(Log.debug, Log.analyze, "Opening video list")
                    showVideoList = true
                }) {
                    Label("Video List", systemImage: "play.rectangle.on.rectangle")
                }
                
                Button(action: {
                    Log.p(Log.debug, Log.analyze, "Opening video feed")
                    showVideoFeed = true
                }) {
                    Label("Video Feed", systemImage: "play.square.stack")
                }
            }
            
            // Add more debug sections here as needed
            Section("App Info") {
                HStack {
                    Text("Build Version")
                    Spacer()
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
                    Text(version)
                        .foregroundColor(.gray)
                        .onAppear {
                            Log.p(Log.debug, Log.verify, "Build version: \(version)")
                        }
                }
                
                HStack {
                    Text("Build Number")
                    Spacer()
                    let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
                    Text(buildNumber)
                        .foregroundColor(.gray)
                        .onAppear {
                            Log.p(Log.debug, Log.verify, "Build number: \(buildNumber)")
                        }
                }
            }
            
            Section("Firebase Data Audit") {
                Button(action: { viewModel.startAudit() }) {
                    HStack {
                        Text("Audit Firebase Data")
                        Spacer()
                        if viewModel.isAuditing {
                            ProgressView()
                        }
                    }
                }
                .disabled(viewModel.isAuditing)
                
                if viewModel.auditStats.totalVideosChecked > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Audit Statistics")
                            .font(.headline)
                        Group {
                            StatRow(label: "Videos", valid: viewModel.auditStats.validVideos, total: viewModel.auditStats.totalVideosChecked)
                            StatRow(label: "Storage Files", valid: viewModel.auditStats.validStorageFiles, total: viewModel.auditStats.totalStorageFilesChecked)
                            StatRow(label: "Reactions", valid: viewModel.auditStats.validReactions, total: viewModel.auditStats.totalReactionsChecked)
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 8)
                }
                
                if !viewModel.auditResults.isEmpty {
                    ForEach(viewModel.auditResults) { result in
                        VStack(alignment: .leading) {
                            Text(result.title)
                                .font(.headline)
                            Text(result.description)
                                .font(.caption)
                                .foregroundColor(.gray)
                            if result.canDelete {
                                Button("Delete", role: .destructive) {
                                    viewModel.deleteItem(result)
                                }
                                .disabled(viewModel.isDeleting)
                            }
                        }
                    }
                }
            }
            
            if !viewModel.auditResults.isEmpty {
                Section {
                    Button("Clear Results", role: .destructive) {
                        viewModel.clearResults()
                        viewModel.auditStats = DebugViewModel.AuditStats()
                    }
                }
            }
        }
        .navigationTitle("Debug Tools")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showVideoList) {
            NavigationView {
                VideoListView()
                    .navigationTitle("Debug: Video List")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showVideoFeed) {
            NavigationView {
                VideoFeedView()
                    .navigationTitle("Debug: Video Feed")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            Log.p(Log.debug, Log.start, "Debug menu appeared")
        }
        .onDisappear {
            Log.p(Log.debug, Log.exit, "Debug menu disappeared")
        }
    }
}

class DebugViewModel: ObservableObject {
    @Published var isAuditing = false
    @Published var isDeleting = false
    @Published var auditResults: [AuditResult] = []
    @Published var auditStats: AuditStats = AuditStats()
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    struct AuditStats {
        var totalVideosChecked = 0
        var validVideos = 0
        var totalStorageFilesChecked = 0
        var validStorageFiles = 0
        var totalReactionsChecked = 0
        var validReactions = 0
        var totalUsersChecked = 0
        var validUsers = 0
        var totalUsernamesChecked = 0
        var validUsernames = 0
    }
    
    struct AuditResult: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let type: ResultType
        let canDelete: Bool
        let path: String
        
        enum ResultType {
            case orphanedVideo
            case invalidVideo
            case orphanedStorageFile
            case invalidStoragePath
            case orphanedReaction
            case invalidUser
            case orphanedUsername
            case invalidUsername
        }
    }
    
    func startAudit() {
        Log.p(Log.debug_audit, Log.scan, "Starting Firebase data audit")
        isAuditing = true
        auditResults.removeAll()
        auditStats = AuditStats()
        
        Task {
            do {
                // 1. Audit Users collection
                let usersSnapshot = try await db.collection("users").getDocuments()
                auditStats.totalUsersChecked = usersSnapshot.documents.count
                
                for doc in usersSnapshot.documents {
                    let userId = doc.documentID
                    let userData = doc.data()
                    guard let username = userData["username"] as? String else {
                        await addResult(
                            title: "Invalid User",
                            description: "User \(userId) has no username field",
                            type: .invalidUser,
                            canDelete: true,
                            path: "users/\(userId)"
                        )
                        continue
                    }
                    
                    // Check if username exists in usernames collection
                    let usernameDoc = try? await db.collection("usernames").document(username).getDocument()
                    if usernameDoc == nil || !usernameDoc!.exists {
                        await addResult(
                            title: "Invalid User",
                            description: "User \(userId) has username '\(username)' which doesn't exist in usernames collection",
                            type: .invalidUser,
                            canDelete: true,
                            path: "users/\(userId)"
                        )
                        continue
                    }
                    
                    // Check if username points to correct user
                    if let usernameData = usernameDoc?.data(),
                       let linkedUserId = usernameData["userId"] as? String,
                       linkedUserId == userId {
                        auditStats.validUsers += 1
                    } else {
                        await addResult(
                            title: "Invalid User",
                            description: "User \(userId) has username '\(username)' but it's linked to different user",
                            type: .invalidUser,
                            canDelete: true,
                            path: "users/\(userId)"
                        )
                    }
                }
                
                // 2. Audit Usernames collection
                let usernamesSnapshot = try await db.collection("usernames").getDocuments()
                auditStats.totalUsernamesChecked = usernamesSnapshot.documents.count
                
                for doc in usernamesSnapshot.documents {
                    let username = doc.documentID
                    let usernameData = doc.data()
                    guard let userId = usernameData["userId"] as? String else {
                        await addResult(
                            title: "Invalid Username",
                            description: "Username '\(username)' has no userId field",
                            type: .invalidUsername,
                            canDelete: true,
                            path: "usernames/\(username)"
                        )
                        continue
                    }
                    // Check if referenced user exists
                    let userDoc = try? await db.collection("users").document(userId).getDocument()
                    if userDoc == nil || !userDoc!.exists {
                        await addResult(
                            title: "Orphaned Username",
                            description: "Username '\(doc.documentID)' references non-existent user \(userId)",
                            type: .orphanedUsername,
                            canDelete: true,
                            path: "usernames/\(doc.documentID)"
                        )
                        continue
                    }
                    
                    // Check if user has this username
                    if let userData = userDoc?.data(),
                       let userUsername = userData["username"] as? String,
                       userUsername == doc.documentID {
                        auditStats.validUsernames += 1
                    } else {
                        await addResult(
                            title: "Invalid Username",
                            description: "Username '\(doc.documentID)' is linked to user \(userId) but user has different username",
                            type: .invalidUsername,
                            canDelete: true,
                            path: "usernames/\(doc.documentID)"
                        )
                    }
                }
                
                // 3. Audit Firestore videos
                let videosSnapshot = try await db.collection("videos").getDocuments()
                auditStats.totalVideosChecked = videosSnapshot.documents.count
                for doc in videosSnapshot.documents {
                    if let video = try? doc.data(as: Video.self) {
                        // Check if video file exists in Storage
                        let videoRef = storage.reference().child("videos/\(video.ownerId)/\(doc.documentID).mp4")
                        do {
                            _ = try await videoRef.getMetadata()
                            // Check if user exists
                            let userDoc = try? await db.collection("users").document(video.ownerId).getDocument()
                            if userDoc != nil && userDoc!.exists {
                                auditStats.validVideos += 1
                            }
                        } catch {
                            await addResult(
                                title: "Orphaned Video Document",
                                description: "Video \(doc.documentID) has no corresponding file in Storage",
                                type: .orphanedVideo,
                                canDelete: true,
                                path: "videos/\(doc.documentID)"
                            )
                        }
                    } else {
                        await addResult(
                            title: "Invalid Video Document",
                            description: "Document \(doc.documentID) cannot be decoded as Video",
                            type: .invalidVideo,
                            canDelete: true,
                            path: "videos/\(doc.documentID)"
                        )
                    }
                }
                
                // 4. Audit Storage files
                let storageRef = storage.reference().child("videos")
                let userFolders = try await storageRef.listAll()
                
                for userFolder in userFolders.prefixes {
                    let userId = userFolder.name
                    let userFiles = try await userFolder.listAll()
                    auditStats.totalStorageFilesChecked += userFiles.items.count
                    
                    for item in userFiles.items {
                        let videoId = item.name.replacingOccurrences(of: ".mp4", with: "")
                        
                        // Check if file follows naming convention
                        if !item.name.hasSuffix(".mp4") {
                            await addResult(
                                title: "Invalid File Format",
                                description: "File \(item.name) in user \(userId) folder is not .mp4",
                                type: .invalidStoragePath,
                                canDelete: true,
                                path: "storage/videos/\(userId)/\(item.name)"
                            )
                            continue
                        }
                        
                        // Check if corresponding Firestore document exists
                        let videoDoc = try? await db.collection("videos").document(videoId).getDocument()
                        if videoDoc != nil && videoDoc!.exists {
                            auditStats.validStorageFiles += 1
                        } else {
                            await addResult(
                                title: "Orphaned Storage File",
                                description: "File \(item.name) has no corresponding Firestore document",
                                type: .orphanedStorageFile,
                                canDelete: true,
                                path: "storage/videos/\(userId)/\(item.name)"
                            )
                        }
                    }
                }
                
                // 5. Audit reactions
                let reactionsSnapshot = try await db.collection("reactions").getDocuments()
                auditStats.totalReactionsChecked = reactionsSnapshot.documents.count
                for doc in reactionsSnapshot.documents {
                    if let videoId = doc.data()["videoId"] as? String {
                        let videoDoc = try? await db.collection("videos").document(videoId).getDocument()
                        if videoDoc != nil && videoDoc!.exists {
                            auditStats.validReactions += 1
                        } else {
                            await addResult(
                                title: "Orphaned Reaction",
                                description: "Reaction \(doc.documentID) references non-existent video \(videoId)",
                                type: .orphanedReaction,
                                canDelete: true,
                                path: "reactions/\(doc.documentID)"
                            )
                        }
                    }
                }
                
                await MainActor.run {
                    isAuditing = false
                    Log.p(Log.debug_audit, Log.verify, Log.success, """
                        Firebase data audit completed:
                        Users: \(auditStats.validUsers)/\(auditStats.totalUsersChecked) valid
                        Usernames: \(auditStats.validUsernames)/\(auditStats.totalUsernamesChecked) valid
                        Videos: \(auditStats.validVideos)/\(auditStats.totalVideosChecked) valid
                        Storage Files: \(auditStats.validStorageFiles)/\(auditStats.totalStorageFilesChecked) valid
                        Reactions: \(auditStats.validReactions)/\(auditStats.totalReactionsChecked) valid
                        Total Issues: \(auditResults.count)
                        """)
                }
            } catch {
                Log.p(Log.debug_audit, Log.scan, Log.error, "Firebase data audit failed: \(error.localizedDescription)")
                await MainActor.run {
                    isAuditing = false
                }
            }
        }
    }
    
    @MainActor
    private func addResult(title: String, description: String, type: AuditResult.ResultType, canDelete: Bool, path: String) {
        auditResults.append(AuditResult(
            title: title,
            description: description,
            type: type,
            canDelete: canDelete,
            path: path
        ))
    }
    
    func deleteItem(_ result: AuditResult) {
        Log.p(Log.debug_cleanup, Log.clean, "Attempting to delete item: \(result.path)")
        isDeleting = true
        
        Task {
            do {
                switch result.type {
                case .orphanedVideo, .invalidVideo:
                    try await db.document(result.path).delete()
                    
                case .orphanedStorageFile, .invalidStoragePath:
                    let ref = storage.reference().child(result.path.replacingOccurrences(of: "storage/", with: ""))
                    try await ref.delete()
                    
                case .orphanedReaction:
                    try await db.document(result.path).delete()
                    
                case .invalidUser:
                    // Delete user document and any associated username
                    let userId = result.path.replacingOccurrences(of: "users/", with: "")
                    if let userData = try? await db.document(result.path).getDocument().data(),
                       let username = userData["username"] as? String {
                        // Delete associated username document if it exists
                        try? await db.collection("usernames").document(username).delete()
                    }
                    try await db.document(result.path).delete()
                    
                case .orphanedUsername, .invalidUsername:
                    try await db.document(result.path).delete()
                }
                
                await MainActor.run {
                    if let index = auditResults.firstIndex(where: { $0.id == result.id }) {
                        auditResults.remove(at: index)
                    }
                    isDeleting = false
                    Log.p(Log.debug_cleanup, Log.clean, Log.success, "Successfully deleted item: \(result.path)")
                }
            } catch {
                Log.p(Log.debug_cleanup, Log.clean, Log.error, "Failed to delete item: \(error.localizedDescription)")
                await MainActor.run {
                    isDeleting = false
                }
            }
        }
    }
    
    func clearResults() {
        auditResults.removeAll()
    }
}

// MARK: - Supporting Views
struct StatRow: View {
    let label: String
    let valid: Int
    let total: Int
    
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(valid)/\(total) valid")
                .foregroundColor(valid == total ? .green : .orange)
        }
    }
}

#Preview {
    NavigationView {
        DebugMenuView()
    }
}
#endif 