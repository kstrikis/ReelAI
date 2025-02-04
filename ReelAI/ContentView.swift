//
//  ContentView.swift
//  ReelAI
//
//  Created by Kriss on 2/3/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authService: AuthenticationService
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                VStack {
                    Image(systemName: "globe")
                        .imageScale(.large)
                        .foregroundStyle(.white)
                    Text("Hello, world!")
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: signOut) {
                        Text("Sign Out")
                            .fontWeight(.medium)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.bottom, 20)
                }
                .padding()
                .navigationTitle("ReelAI")
                .navigationBarTitleDisplayMode(.large)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarBackground(Color.black, for: .navigationBar)
            }
        }
    }
    
    private func signOut() {
        AppLogger.methodEntry(AppLogger.ui)
        authService.signOut()
        AppLogger.methodExit(AppLogger.ui)
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationService.preview)
}
