#if DEBUG
import SwiftUI

struct DebugMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showVideoList = false
    
    var body: some View {
        List {
            Section("Video Tools") {
                Button(action: {
                    Log.p(Log.app, Log.event, "Debug: Opening video list")
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
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
                    Text(version)
                        .foregroundColor(.gray)
                        .onAppear {
                            Log.p(Log.app, Log.event, "Debug: Build version: \(version)")
                        }
                }
                
                HStack {
                    Text("Build Number")
                    Spacer()
                    let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
                    Text(buildNumber)
                        .foregroundColor(.gray)
                        .onAppear {
                            Log.p(Log.app, Log.event, "Debug: Build number: \(buildNumber)")
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
        .onAppear {
            Log.p(Log.app, Log.start, "Debug menu appeared")
        }
        .onDisappear {
            Log.p(Log.app, Log.exit, "Debug menu disappeared")
        }
    }
}

#Preview {
    NavigationView {
        DebugMenuView()
    }
}
#endif 