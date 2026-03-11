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
                    KeychainService.migrateToSharedGroup()
                    AppGroupStorage.shared.syncCredentials()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        gateway.checkConnectionHealth()
                        processPendingShares()
                    }
                }
        }
    }
    
    private func processPendingShares() {
        let shares = AppGroupStorage.shared.getPendingShares()
        guard !shares.isEmpty, gateway.isConnected else { return }
        
        for share in shares {
            if let imagePath = share.imagePath,
               let imageData = AppGroupStorage.shared.loadSharedImage(at: imagePath) {
                gateway.sendMessageWithImage(share.message, imageData: imageData)
            } else {
                gateway.sendMessage(share.message)
            }
        }
        
        AppGroupStorage.shared.clearPendingShares()
    }
}
