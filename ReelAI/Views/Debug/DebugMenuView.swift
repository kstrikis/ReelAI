import SwiftUI

#if DEBUG
struct DebugMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showVideoList = false
    
    var body: some View {
        List {
            Section("Video Tools") {
                Button(action: {
                    showVideoList = true
                }) {
                    Label("Video List", systemImage: "play.rectangle.on.rectangle")
                }
            }
            
            // Add more debug sections here as needed
            Section("App Info") {
                HStack {
                    Text("Build Version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown")
                        .foregroundColor(.gray)
                }
                
                HStack {
                    Text("Build Number")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown")
                        .foregroundColor(.gray)
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
    }
}

#Preview {
    NavigationView {
        DebugMenuView()
    }
}
#endif 