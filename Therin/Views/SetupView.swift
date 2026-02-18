import SwiftUI

// MARK: - Setup View (Single screen)

struct SetupView: View {
    @EnvironmentObject var gateway: GatewayClient
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    @Environment(\.dismiss) private var dismiss
    
    @State private var urlInput = ""
    @State private var tokenInput = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var showingHelp = false
    
    var body: some View {
        GeometryReader { geometry in
            let isIPad = geometry.size.width > 500
            let maxFormWidth: CGFloat = isIPad ? 400 : .infinity
            let horizontalPadding: CGFloat = isIPad ? 0 : 24
            
            ScrollView {
                VStack(spacing: 24) {
                    Spacer()
                        .frame(height: isIPad ? 80 : 60)
                    
                    // Logo
                    Image("Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: isIPad ? 120 : 100, height: isIPad ? 120 : 100)
                        .clipShape(RoundedRectangle(cornerRadius: isIPad ? 28 : 22))
                    
                    VStack(spacing: 8) {
                        Text("OpenClaw Chat")
                            .font(isIPad ? .system(size: 36, weight: .bold) : .largeTitle.bold())
                            .foregroundColor(.white)
                        
                        Text("Connect to your gateway")
                            .font(isIPad ? .title3 : .body)
                            .foregroundColor(Color(white: 0.7))
                    }
                    
                    Spacer()
                        .frame(height: isIPad ? 48 : 32)
                    
                    // Form container
                    VStack(spacing: 20) {
                        // Gateway URL input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Gateway URL")
                                .font(isIPad ? .title3 : .body)
                                .fontWeight(.medium)
                                .foregroundColor(Color(white: 0.8))
                            
                            TextField("", text: $urlInput, prompt: Text("openclaw.tailnet.ts.net").foregroundColor(Color(white: 0.35)))
                                .font(isIPad ? .title3 : .body)
                                .padding(.horizontal, 16)
                                .padding(.vertical, isIPad ? 16 : 12)
                                .background(Color(white: 0.15))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                            
                            Text("Tailscale hostname or IP address")
                                .font(isIPad ? .title3 : .body)
                                .foregroundColor(Color(white: 0.55))
                        }
                        
                        // Token input
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Access Token")
                                .font(isIPad ? .title3 : .body)
                                .fontWeight(.medium)
                                .foregroundColor(Color(white: 0.8))
                            
                            SecureField("", text: $tokenInput, prompt: Text("Paste your gateway token").foregroundColor(Color(white: 0.35)))
                                .font(isIPad ? .title3 : .body)
                                .padding(.horizontal, 16)
                                .padding(.vertical, isIPad ? 16 : 12)
                                .background(Color(white: 0.15))
                                .cornerRadius(12)
                                .foregroundColor(.white)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            
                            Text("Find in ~/.openclaw/openclaw.json → gateway.auth.token")
                                .font(isIPad ? .title3 : .body)
                                .foregroundColor(Color(white: 0.55))
                        }
                        
                        if let error = errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(isIPad ? .title3 : .body)
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        // Connect button
                        Button(action: connect) {
                            HStack(spacing: 8) {
                                if isConnecting {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(isConnecting ? "Connecting..." : "Connect")
                                    .font(isIPad ? .title3 : .body)
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, isIPad ? 18 : 14)
                            .background(canConnect ? Color.blue : Color(white: 0.25))
                            .foregroundColor(canConnect ? .white : Color(white: 0.5))
                            .cornerRadius(12)
                        }
                        .padding(.top, 8)
                        .disabled(!canConnect || isConnecting)
                    }
                    .frame(maxWidth: maxFormWidth)
                    .padding(.horizontal, horizontalPadding)
                    
                    // Help link
                    Button(action: { showingHelp = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.circle")
                            Text("First time setup help")
                        }
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.5))
                    }
                    
                    Spacer()
                        .frame(height: 40)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.black)
        .onAppear {
            if !gatewayURL.isEmpty { urlInput = gatewayURL }
            if !gatewayToken.isEmpty { tokenInput = gatewayToken }
        }
        .sheet(isPresented: $showingHelp) {
            SetupHelpView()
        }
    }
    
    private var canConnect: Bool {
        !urlInput.isEmpty && !tokenInput.isEmpty
    }
    
    private func connect() {
        errorMessage = nil
        isConnecting = true
        
        var url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Strip protocol prefixes
        url = url.replacingOccurrences(of: "https://", with: "")
        url = url.replacingOccurrences(of: "http://", with: "")
        url = url.replacingOccurrences(of: "wss://", with: "")
        url = url.replacingOccurrences(of: "ws://", with: "")
        url = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        // Save credentials
        gatewayURL = url
        gatewayToken = token
        
        // Sync to App Group for Share Extension
        AppGroupStorage.shared.gatewayURL = url
        AppGroupStorage.shared.gatewayToken = token
        
        // Connect
        gateway.connect(url: url, token: token)
        
        // Reset state after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isConnecting = false
        }
    }
}

// MARK: - Setup Help View

struct SetupHelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    helpSection(
                        icon: "1.circle.fill",
                        title: "Enter Gateway Details",
                        content: "Enter your OpenClaw gateway URL (e.g., openclaw.your-tailnet.ts.net) and your access token from ~/.openclaw/openclaw.json → gateway.auth.token"
                    )
                    
                    helpSection(
                        icon: "2.circle.fill",
                        title: "Device Pairing",
                        content: "On first connection, you'll see \"Waiting for approval...\" — this is normal. Your gateway needs to approve this device for security."
                    )
                    
                    helpSection(
                        icon: "3.circle.fill",
                        title: "Approve on Gateway",
                        content: "On your gateway server, run:\n\nopenclaw devices list\nopenclaw devices approve <requestId>\n\nReplace <requestId> with the ID shown in the list."
                    )
                    
                    helpSection(
                        icon: "checkmark.circle.fill",
                        title: "You're Connected",
                        content: "Once approved, the app connects automatically. Future connections from this device won't need re-approval."
                    )
                    
                    Divider()
                        .background(Color(white: 0.3))
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Auto-Approval (Optional)")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("To auto-approve devices with valid tokens, add this cron job on your gateway:")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.7))
                        
                        Text("* * * * * openclaw devices approve --latest")
                            .font(.system(.caption, design: .monospaced))
                            .padding(12)
                            .background(Color(white: 0.15))
                            .cornerRadius(8)
                            .foregroundColor(Color(white: 0.8))
                    }
                }
                .padding(24)
            }
            .background(Color.black)
            .navigationTitle("Setup Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func helpSection(icon: String, title: String, content: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(content)
                    .font(.subheadline)
                    .foregroundColor(Color(white: 0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    SetupView()
        .environmentObject(GatewayClient())
}

#Preview("Help") {
    SetupHelpView()
}
