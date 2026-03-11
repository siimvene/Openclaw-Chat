import SwiftUI

struct StatusView: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var selectedTab: Int
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    @AppStorage("chatTextSize") private var chatTextSize: Double = 14
    @State private var showLogoutConfirm = false
    @State private var showWipeConfirm = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    StatusRow(
                        icon: "circle.fill",
                        iconColor: gateway.isConnected ? .onlineGreen : .red,
                        label: "Settings",
                        value: gateway.isConnected ? "Connected" : "Disconnected"
                    )
                    StatusRow(icon: "network", label: "Gateway", value: gatewayURL.isEmpty ? "Not set" : gatewayURL)
                    StatusRow(icon: "clock", label: "Uptime", value: formatUptime(gateway.uptimeMs / 1000))
                    if gateway.serverVersion != "dev" && gateway.serverVersion != "Unknown" {
                        StatusRow(icon: "tag", label: "Server Version", value: gateway.serverVersion)
                    }
                    if !gateway.activeModel.isEmpty {
                        StatusRow(icon: "cpu", label: "Model", value: gateway.activeModel)
                    }
                }

                Section("Appearance") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Text Size", systemImage: "textformat.size")
                            Spacer()
                            Text("\(Int(chatTextSize))pt")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $chatTextSize, in: 12...20, step: 1)
                            .tint(.appPrimary)
                    }
                }

                Section("Security") {
                    NavigationLink {
                        SecurityView(gateway: gateway, selectedTab: $selectedTab)
                            .environmentObject(gateway)
                            .environmentObject(sessionManager)
                    } label: {
                        Label("Security Audit", systemImage: "shield.checkered")
                    }
                }

                Section("About") {
                    StatusRow(icon: "app.badge", label: "App Version", value: appVersion)
                    StatusRow(icon: "rectangle.stack", label: "Active Session", value: gateway.activeSessionKey)
                }

                Section("Actions") {
                    Button("Clear Device Data", role: .destructive) {
                        showWipeConfirm = true
                    }
                    Button("Log Out", role: .destructive) {
                        showLogoutConfirm = true
                    }
                }
            }
            .alert("Log Out", isPresented: $showLogoutConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    logout()
                }
            } message: {
                Text("This will disconnect from the gateway and clear your credentials.")
            }
            .confirmationDialog("Clear device data and all chats?", isPresented: $showWipeConfirm) {
                Button("Clear Device Data", role: .destructive) {
                    gateway.wipeDeviceDataAndChats()
                }
            } message: {
                Text("This removes all chats and messages stored locally on this device.")
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }
    
    // MARK: - Actions
    
    private func logout() {
        gateway.disconnect()
        gatewayURL = ""
        gatewayToken = ""
    }
    
    // MARK: - Helpers
    
    private func formatUptime(_ seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
}

// MARK: - Supporting Views

struct StatusRow: View {
    let icon: String
    var iconColor: Color = .secondary
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 24)
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    StatusView(selectedTab: .constant(2))
        .environmentObject(GatewayClient())
        .environmentObject(SessionManager())
}
