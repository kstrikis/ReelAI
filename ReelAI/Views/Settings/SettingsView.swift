import SwiftUI
import UIKit

struct SettingsView: View {
    @StateObject private var settings = UserSettings.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ZStack {
                // Use our reusable space background
                SpaceBackground()
                
                // Settings content
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Video Feed")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            Picker("Order", selection: $settings.videoFeedOrder) {
                                ForEach(UserSettings.VideoFeedOrder.allCases, id: \.self) { order in
                                    HStack {
                                        Text(order.rawValue)
                                            .foregroundColor(.white)
                                        Text(order.description)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                    .tag(order)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#if DEBUG
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
#endif 