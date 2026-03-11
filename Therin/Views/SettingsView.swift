import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var gateway: GatewayClient
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    @Environment(\.dismiss) private var dismiss
    
    @State private var showClearConfirm = false
    @State private var showDisconnectConfirm = false
    
    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("Gateway", value: gatewayURL)
                LabeledContent("Settings", value: gateway.isConnected ? "Connected" : "Disconnected")
                LabeledContent("Session", value: gateway.activeSessionKey)
            }
            
            if !gateway.activeModel.isEmpty {
                Section("Model") {
                    LabeledContent("Active Model", value: gateway.activeModel)
                }
            }
            
            Section {
                Button("Clear Device Data", role: .destructive) {
                    showClearConfirm = true
                }
                
                Button("Disconnect & Reset", role: .destructive) {
                    showDisconnectConfirm = true
                }
            }
            
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear device data and all chats?", isPresented: $showClearConfirm) {
            Button("Clear Device Data", role: .destructive) {
                gateway.wipeDeviceDataAndChats()
            }
        } message: {
            Text("This removes all chats and messages stored locally on this device.")
        }
        .confirmationDialog("Disconnect and reset settings?", isPresented: $showDisconnectConfirm) {
            Button("Reset", role: .destructive) {
                gateway.disconnect()
                gatewayURL = ""
                gatewayToken = ""
                _ = KeychainService.delete(.gatewayURL)
                _ = KeychainService.delete(.gatewayToken)
                AppGroupStorage.shared.gatewayURL = nil
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(GatewayClient())
    }
}
