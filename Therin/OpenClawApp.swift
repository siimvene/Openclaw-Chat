import SwiftUI

@main
struct OpenClawApp: App {
    @StateObject private var gateway = GatewayClient()
    @StateObject private var sessionManager = SessionManager()
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gateway)
                .environmentObject(sessionManager)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Sync credentials to App Group on launch
                    AppGroupStorage.shared.syncCredentials()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        processPendingShares()
                    }
                }
        }
    }
    
    private func processPendingShares() {
        let shares = AppGroupStorage.shared.getPendingShares()
        guard !shares.isEmpty, gateway.isConnected else { return }
        
        for share in shares {
            // Send the shared content as a message
            gateway.sendMessage(share.message)
            
            // TODO: Handle image uploads when gateway supports it
            // if let imagePath = share.imagePath,
            //    let imageData = AppGroupStorage.shared.loadSharedImage(at: imagePath) {
            //     gateway.sendImage(imageData, message: share.message)
            // }
        }
        
        AppGroupStorage.shared.clearPendingShares()
    }
}
