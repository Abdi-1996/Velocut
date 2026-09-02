import SwiftUI

@main
struct EditFlowApp: App {
    @StateObject private var store = ProjectStore()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

