import SwiftUI

@main
struct OpenClawApp: App {
    @StateObject private var gateway = GatewayClient()
    @StateObject private var sessionManager = SessionManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gateway)
                .environmentObject(sessionManager)
                .preferredColorScheme(.dark)
        }
    }
}
