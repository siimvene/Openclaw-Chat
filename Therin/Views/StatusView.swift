import SwiftUI

struct StatusView: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var selectedTab: Int
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    @State private var usageData: UsageData?
    @State private var isLoading = false
    @State private var lastRefresh: Date?
    @State private var autoRefreshTask: Task<Void, Never>?
    @State private var showLogoutConfirm = false
    
    var body: some View {
        NavigationStack {
            List {
                // Connection section
                Section("Connection") {
                    StatusRow(
                        icon: "circle.fill",
                        iconColor: gateway.isConnected ? .green : .red,
                        label: "Status",
                        value: gateway.isConnected ? "Connected" : "Disconnected"
                    )
                    
                    if gateway.serverVersion != "dev" && gateway.serverVersion != "Unknown" {
                        StatusRow(icon: "tag", label: "Version", value: gateway.serverVersion)
                    }
                    StatusRow(icon: "clock", label: "Uptime", value: formatUptime(gateway.uptimeMs / 1000))
                }
                
                
                // Today's usage
                if let usage = usageData {
                    Section("Today") {
                        StatusRow(icon: "dollarsign.circle", label: "Cost", value: usage.todayCost)
                        StatusRow(icon: "text.bubble", label: "Words In", value: formatTokensAsWords(usage.todayInput))
                        StatusRow(icon: "text.bubble.fill", label: "Words Out", value: formatTokensAsWords(usage.todayOutput))
                    }

                    Section("All Time") {
                        StatusRow(icon: "dollarsign.circle.fill", label: "Total Cost", value: usage.totalCost)
                    }
                }
                
                // Security audit link
                Section("Security") {
                    NavigationLink {
                        SecurityView(gateway: gateway, selectedTab: $selectedTab)
                            .environmentObject(gateway)
                            .environmentObject(sessionManager)
                    } label: {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Security Audit")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Settings link
                Section {
                    NavigationLink {
                        SettingsView()
                            .environmentObject(gateway)
                    } label: {
                        HStack {
                            Image(systemName: "gearshape")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text("Settings")
                        }
                    }
                }
                
                // Disconnected state
                if !gateway.isConnected {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "wifi.slash")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("Connect to gateway to view status")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                
                // Last refresh
                if let refresh = lastRefresh {
                    Section {
                        HStack {
                            Spacer()
                            Text("Updated: \(refresh.formatted(.dateTime.hour().minute().second()))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                
                // Logout button
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Log Out")
                            Spacer()
                        }
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
            .navigationTitle("Status")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if isLoading && usageData == nil {
                    ProgressView("Loading...")
                }
            }
            .refreshable {
                await refresh()
            }
            .task {
                await refresh()
                startAutoRefresh()
            }
            .onDisappear {
                autoRefreshTask?.cancel()
            }
        }
    }
    
    // MARK: - Auto-refresh
    
    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                if !Task.isCancelled {
                    await refresh()
                }
            }
        }
    }
    
    // MARK: - Data Loading
    
    @MainActor
    private func refresh() async {
        guard gateway.isConnected else { return }
        
        isLoading = true
        
        if let cost = await gateway.getUsageCost() {
            usageData = parseCostResponse(cost)
        }
        
        lastRefresh = Date()
        isLoading = false
    }
    
    private func parseCostResponse(_ data: [String: Any]) -> UsageData {
        // Get totals
        let totals = data["totals"] as? [String: Any] ?? [:]
        let totalInput = totals["input"] as? Int ?? 0
        let totalOutput = totals["output"] as? Int ?? 0
        let totalTokens = totals["totalTokens"] as? Int ?? (totalInput + totalOutput)
        let totalCostValue = totals["totalCost"] as? Double ?? 0
        
        // Get today's data (last item in daily array)
        var todayInput = 0
        var todayOutput = 0
        var todayCostValue = 0.0
        
        if let daily = data["daily"] as? [[String: Any]], let today = daily.last {
            todayInput = today["input"] as? Int ?? 0
            todayOutput = today["output"] as? Int ?? 0
            todayCostValue = today["totalCost"] as? Double ?? 0
        }
        
        return UsageData(
            todayInput: todayInput,
            todayOutput: todayOutput,
            todayCost: String(format: "$%.2f", todayCostValue),
            totalTokens: totalTokens,
            totalCost: String(format: "$%.2f", totalCostValue)
        )
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
    
    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatTokensAsWords(_ tokens: Int) -> String {
        let words = Int(Double(tokens) * 0.75)
        if words >= 1_000_000 {
            return String(format: "%.1fM", Double(words) / 1_000_000)
        } else if words >= 1_000 {
            return String(format: "%.1fK", Double(words) / 1_000)
        }
        return "\(words)"
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

// MARK: - Data Models

struct UsageData {
    let todayInput: Int
    let todayOutput: Int
    let todayCost: String
    let totalTokens: Int
    let totalCost: String
}

#Preview {
    StatusView(selectedTab: .constant(3))
        .environmentObject(GatewayClient())
        .environmentObject(SessionManager())
}
