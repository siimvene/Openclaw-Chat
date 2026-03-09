import SwiftUI

// MARK: - Setup View (Pixel-Perfect Glassmorphic)

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
    @State private var showPassword = false
    
    var body: some View {
        GeometryReader { geometry in
            let isIPad = geometry.size.width > 600
            let maxFormWidth: CGFloat = isIPad ? 560 : .infinity
            let horizontalPadding: CGFloat = isIPad ? 80 : 20
            
            ZStack {
                // Dark gradient background with subtle blue tint
                LinearGradient(
                    colors: [
                        Color(red: 0.08, green: 0.12, blue: 0.18),
                        Color(red: 0.04, green: 0.06, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Spacer().frame(height: isIPad ? 80 : 60)
                            
                            // Glass card container
                            VStack(spacing: 0) {
                                Spacer().frame(height: isIPad ? 56 : 40)
                                
                                // Round white logo treatment
                                ZStack {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: isIPad ? 88 : 72, height: isIPad ? 88 : 72)
                                    
                                    Image("Logo")
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: isIPad ? 82 : 66, height: isIPad ? 82 : 66)
                                        .clipShape(Circle())
                                }
                                .overlay(
                                    Circle()
                                        .stroke(Color.appPrimary, lineWidth: isIPad ? 3 : 2)
                                )
                                
                                Spacer().frame(height: isIPad ? 32 : 24)
                                
                                // Title - italic bold
                                Text("OpenClaw Chat")
                                    .font(.system(size: isIPad ? 34 : 28, weight: .bold))
                                    .italic()
                                    .foregroundColor(.white)
                                
                                Spacer().frame(height: 8)
                                
                                Text("Connect privately to your gateway")
                                    .font(.system(size: isIPad ? 16 : 15))
                                    .foregroundColor(Color(white: 0.6))
                                
                                Spacer().frame(height: isIPad ? 48 : 32)
                                
                                // Form fields with light backgrounds
                                VStack(spacing: 24) {
                                    // Gateway URL
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("GATEWAY URL")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Color(white: 0.5))
                                            .tracking(0.8)
                                        
                                        HStack(spacing: 14) {
                                            Image(systemName: "link")
                                                .font(.system(size: 18))
                                                .foregroundColor(Color(white: 0.5))
                                            
                                            TextField(
                                                "",
                                                text: $urlInput,
                                                prompt: Text("your.gateway.address.net")
                                                    .foregroundColor(Color(white: 0.55))
                                            )
                                                .font(.system(size: 15))
                                                .foregroundColor(Color(white: 0.2))
                                                .textInputAutocapitalization(.never)
                                                .autocorrectionDisabled()
                                                .keyboardType(.URL)
                                        }
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(white: 0.95))
                                        )
                                    }
                                    
                                    // Access Token
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("ACCESS TOKEN")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundColor(Color(white: 0.5))
                                            .tracking(0.8)
                                        
                                        HStack(spacing: 14) {
                                            Image(systemName: "key.horizontal")
                                                .font(.system(size: 18))
                                                .foregroundColor(Color(white: 0.5))
                                            
                                            Group {
                                                if showPassword {
                                                    TextField("Enter your secure token", text: $tokenInput)
                                                } else {
                                                    SecureField("Enter your secure token", text: $tokenInput)
                                                }
                                            }
                                            .font(.system(size: 15))
                                            .foregroundColor(Color(white: 0.2))
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                            
                                            Button {
                                                showPassword.toggle()
                                            } label: {
                                                Image(systemName: showPassword ? "eye.slash" : "eye")
                                                    .font(.system(size: 16))
                                                    .foregroundColor(Color(white: 0.5))
                                            }
                                        }
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 16)
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color(white: 0.95))
                                        )
                                    }
                                }
                                .padding(.horizontal, isIPad ? 40 : 24)
                                
                                // Error message
                                if let error = errorMessage {
                                    HStack(spacing: 8) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text(error)
                                            .font(.system(size: 13))
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.top, 16)
                                }
                                
                                Spacer().frame(height: 32)
                                
                                // Connect Button
                                Button(action: connect) {
                                    HStack(spacing: 10) {
                                        if isConnecting {
                                            ProgressView()
                                                .tint(.white)
                                        }
                                        Text(isConnecting ? "Connecting..." : "Connect Now")
                                            .font(.system(size: 16, weight: .semibold))
                                        if !isConnecting {
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 14, weight: .semibold))
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 18)
                                    .background(Color.appPrimary)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal, isIPad ? 40 : 24)
                                .disabled(isConnecting)
                                
                                Spacer().frame(height: 28)
                                
                                // Help link with dashed dividers
                                HStack(spacing: 12) {
                                    DashedLine()
                                        .frame(width: 50)
                                    
                                    HStack(spacing: 6) {
                                        Text("Need help?")
                                            .font(.system(size: 13))
                                            .foregroundColor(Color(white: 0.5))
                                        Button("Contact Support") {
                                            showingHelp = true
                                        }
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(Color.appPrimary)
                                    }
                                    
                                    DashedLine()
                                        .frame(width: 50)
                                }
                                
                                Spacer().frame(height: isIPad ? 56 : 40)
                            }
                            .frame(maxWidth: maxFormWidth)
                            .background(
                                // Glassmorphic card background with gradient
                                ZStack {
                                    // Base gradient fill
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color(red: 0.12, green: 0.16, blue: 0.22),
                                                    Color(red: 0.08, green: 0.10, blue: 0.14)
                                                ],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                    
                                    // Subtle highlight at top
                                    RoundedRectangle(cornerRadius: 20)
                                        .fill(
                                            LinearGradient(
                                                colors: [
                                                    Color.white.opacity(0.08),
                                                    Color.white.opacity(0.02),
                                                    Color.clear
                                                ],
                                                startPoint: .top,
                                                endPoint: .center
                                            )
                                        )
                                }
                            )
                            .overlay(
                                // Gradient border - brighter at top
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.25),
                                                Color.white.opacity(0.08),
                                                Color.white.opacity(0.04)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .padding(.horizontal, horizontalPadding)
                            
                            Spacer().frame(height: isIPad ? 60 : 40)
                            
                            Spacer().frame(height: 24)
                        }
                    }
                    
                }
            }
        }
        .onAppear {
            if gatewayURL.isEmpty, let storedURL = KeychainService.get(.gatewayURL) {
                gatewayURL = storedURL
            }
            if !gatewayURL.isEmpty { urlInput = gatewayURL }
            
            if let storedToken = KeychainService.get(.gatewayToken), !storedToken.isEmpty {
                tokenInput = storedToken
                if !gatewayToken.isEmpty { gatewayToken = "" }
            } else if !gatewayToken.isEmpty {
                tokenInput = gatewayToken
                _ = KeychainService.save(gatewayToken, for: .gatewayToken)
                gatewayToken = ""
            }
        }
        .sheet(isPresented: $showingHelp) {
            SetupHelpView()
        }
    }
    
    private func connect() {
        errorMessage = nil
        isConnecting = true
        
        var url = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        url = url.replacingOccurrences(of: "https://", with: "")
        url = url.replacingOccurrences(of: "http://", with: "")
        url = url.replacingOccurrences(of: "wss://", with: "")
        url = url.replacingOccurrences(of: "ws://", with: "")
        url = url.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        gatewayURL = url
        gatewayToken = ""
        _ = KeychainService.save(url, for: .gatewayURL)
        if token.isEmpty {
            _ = KeychainService.delete(.gatewayToken)
        } else {
            _ = KeychainService.save(token, for: .gatewayToken)
        }
        
        AppGroupStorage.shared.gatewayURL = url
        
        gateway.connect(url: url, token: token)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isConnecting = false
        }
    }
}

// MARK: - Dashed Line

struct DashedLine: View {
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
            }
            .stroke(Color(white: 0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        }
        .frame(height: 1)
    }
}

// MARK: - Help View

struct SetupHelpView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    helpStep("1", "Enter Gateway Details", "Enter your OpenClaw gateway URL and access token from ~/.openclaw/openclaw.json")
                    helpStep("2", "Device Pairing", "On first connection, your gateway needs to approve this device.")
                    helpStep("3", "Approve on Gateway", "Run: openclaw devices list\nthen: openclaw devices approve <requestId>")
                    helpStep("4", "Connected!", "Once approved, future connections are automatic.")
                }
                .padding(24)
            }
            .background(Color.appBackground)
            .navigationTitle("Setup Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color.appPrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
    
    private func helpStep(_ num: String, _ title: String, _ desc: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(num)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.appPrimary))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 14))
                    .foregroundColor(Color.textSecondary)
            }
        }
    }
}

#Preview {
    SetupView()
        .environmentObject(GatewayClient())
}
