import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var gateway: GatewayClient
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    @AppStorage("selectedModel") private var selectedModel = ""
    @Environment(\.dismiss) private var dismiss
    
    @State private var showClearConfirm = false
    @State private var showDisconnectConfirm = false
    @State private var availableModels: [ModelInfo] = []
    @State private var isLoadingModels = false
    
    // Common/recommended models to show at top
    private let recommendedModels = [
        "anthropic/claude-opus-4-5",
        "anthropic/claude-opus-4.6",
        "anthropic/claude-sonnet-4",
        "anthropic/claude-haiku-3.5",
        "anthropic/claude-opus-4",
        "anthropic/claude-sonnet-3.5",
        "openai/gpt-4o",
        "openai/gpt-4-turbo"
    ]
    
    var body: some View {
        List {
            Section("Connection") {
                LabeledContent("Gateway", value: gatewayURL)
                LabeledContent("Status", value: gateway.isConnected ? "Connected" : "Disconnected")
                LabeledContent("Session", value: gateway.activeSessionKey)
            }
            
            // Model selection
            Section("Model") {
                if isLoadingModels {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Loading models...")
                            .foregroundColor(.secondary)
                    }
                } else if availableModels.isEmpty {
                    Button("Load Available Models") {
                        Task { await loadModels() }
                    }
                } else {
                    Picker("Active Model", selection: $selectedModel) {
                        Text("Default").tag("")
                        
                        // Recommended section
                        Section("Recommended") {
                            ForEach(filteredRecommendedModels, id: \.id) { model in
                                Text(model.displayName)
                                    .tag(model.id)
                            }
                        }
                        
                        // All models section
                        Section("All Models") {
                            ForEach(availableModels.prefix(50), id: \.id) { model in
                                Text(model.displayName)
                                    .tag(model.id)
                            }
                        }
                    }
                    .pickerStyle(.navigationLink)
                    
                    if !selectedModel.isEmpty {
                        HStack {
                            Text("Current")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(selectedModel)
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Button("Refresh Models") {
                        Task { await loadModels() }
                    }
                    .font(.caption)
                }
            }
            
            Section {
                Button("Clear Chat History", role: .destructive) {
                    showClearConfirm = true
                }
                
                Button("Disconnect & Reset", role: .destructive) {
                    showDisconnectConfirm = true
                }
            }
            
            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear all messages in current session?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) {
                gateway.clearMessages()
            }
        }
        .confirmationDialog("Disconnect and reset settings?", isPresented: $showDisconnectConfirm) {
            Button("Reset", role: .destructive) {
                gateway.disconnect()
                gatewayURL = ""
                gatewayToken = ""
                selectedModel = ""
                dismiss()
            }
        }
        .task {
            if availableModels.isEmpty && gateway.isConnected {
                await loadModels()
            }
        }
    }
    
    private var filteredRecommendedModels: [ModelInfo] {
        availableModels.filter { model in
            recommendedModels.contains { rec in
                model.id.contains(rec) || model.displayName.lowercased().contains(rec.lowercased())
            }
        }
    }
    
    @MainActor
    private func loadModels() async {
        isLoadingModels = true
        
        if let models = await gateway.getModels() {
            availableModels = models.compactMap { dict -> ModelInfo? in
                guard let id = dict["id"] as? String else { return nil }
                let name = dict["name"] as? String ?? id
                let provider = dict["provider"] as? String ?? ""
                return ModelInfo(id: id, name: name, provider: provider)
            }
            .sorted { a, b in
                // Sort recommended models first
                let aIsRec = recommendedModels.contains { a.id.contains($0) }
                let bIsRec = recommendedModels.contains { b.id.contains($0) }
                if aIsRec != bIsRec { return aIsRec }
                return a.name < b.name
            }
        }
        
        isLoadingModels = false
    }
}

struct ModelInfo: Identifiable {
    let id: String
    let name: String
    let provider: String
    
    var displayName: String {
        if provider.isEmpty {
            return name
        }
        return "\(name) (\(provider))"
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environmentObject(GatewayClient())
    }
}
