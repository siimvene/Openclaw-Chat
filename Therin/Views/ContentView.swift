import SwiftUI

struct ContentView: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    
    var body: some View {
        Group {
            if gateway.isConnected {
                MainTabView()
            } else if gatewayURL.isEmpty {
                SetupView()
            } else {
                ConnectingView()
                    .onAppear {
                        print("[App] ConnectingView appeared, isConnecting=\(gateway.isConnecting), isConnected=\(gateway.isConnected)")
                        if !gateway.isConnecting && !gateway.isConnected {
                            gateway.connect(url: gatewayURL, token: gatewayToken)
                        }
                    }
            }
        }
        .onAppear {
            gateway.configure(sessionManager: sessionManager)
            // Create a default session if none exist
            if sessionManager.sessions.isEmpty {
                let session = sessionManager.createSession(name: "General")
                sessionManager.selectSession(session)
                gateway.switchToSession(session.id)
            }
        }
    }
}

struct MainTabView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedTab = 1 // Default to Chat
    @State private var dragOffset: CGFloat = 0
    @State private var isEdgeSwipe = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area with swipe
            GeometryReader { geometry in
                let edgeZone: CGFloat = 50 // Edge zone for tab swipes
                
                HStack(spacing: 0) {
                    SessionsView(selectedTab: $selectedTab)
                        .frame(width: geometry.size.width)
                    
                    ChatView(selectedTab: $selectedTab)
                        .frame(width: geometry.size.width)
                    
                    VoiceView()
                        .frame(width: geometry.size.width)
                    
                    StatusView(selectedTab: $selectedTab)
                        .frame(width: geometry.size.width)
                }
                .offset(x: -CGFloat(selectedTab) * geometry.size.width + dragOffset)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: selectedTab)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 20, coordinateSpace: .local)
                        .onChanged { value in
                            // Only allow tab swipes from screen edges
                            let startX = value.startLocation.x
                            let isFromLeftEdge = startX < edgeZone
                            let isFromRightEdge = startX > geometry.size.width - edgeZone
                            
                            if isFromLeftEdge || isFromRightEdge {
                                isEdgeSwipe = true
                                let horizontal = abs(value.translation.width)
                                let vertical = abs(value.translation.height)
                                
                                if horizontal > vertical {
                                    dragOffset = value.translation.width
                                }
                            }
                        }
                        .onEnded { value in
                            defer { isEdgeSwipe = false }
                            
                            // Only process if this was an edge swipe
                            guard isEdgeSwipe else {
                                dragOffset = 0
                                return
                            }
                            
                            let horizontal = abs(value.translation.width)
                            let vertical = abs(value.translation.height)
                            let isHorizontalSwipe = horizontal > vertical
                            
                            let translation = value.translation.width
                            let velocity = value.predictedEndTranslation.width
                            
                            let shouldSwipeLeft = translation < -30 || velocity < -80
                            let shouldSwipeRight = translation > 30 || velocity > 80
                            
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                if isHorizontalSwipe {
                                    if shouldSwipeLeft && selectedTab < 3 {
                                        selectedTab += 1
                                    } else if shouldSwipeRight && selectedTab > 0 {
                                        selectedTab -= 1
                                    }
                                }
                                dragOffset = 0
                            }
                            
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                )
            }
            
            // Tab bar
            HStack(spacing: 0) {
                ForEach(0..<4) { index in
                    TabButton(
                        index: index,
                        selectedTab: $selectedTab,
                        icon: ["list.bullet", "bubble.left.fill", "waveform", "chart.bar.fill"][index],
                        title: ["Sessions", "Chat", "Voice", "Status"][index],
                        badge: index == 0 ? sessionManager.totalUnread : 0
                    )
                }
            }
            .frame(maxWidth: 500)  // Limit tab bar width on iPad
            .frame(maxWidth: .infinity)  // Center it
            .padding(.vertical, 8)
            .background(Color(white: 0.1))
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

struct TabButton: View {
    let index: Int
    @Binding var selectedTab: Int
    let icon: String
    let title: String
    var badge: Int = 0
    
    var body: some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                    
                    if badge > 0 {
                        Text("\(min(badge, 99))")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .background(Color.red)
                            .clipShape(Capsule())
                            .offset(x: 8, y: -4)
                    }
                }
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundColor(selectedTab == index ? .blue : .gray)
            .frame(maxWidth: .infinity)
        }
    }
}



struct ConnectingView: View {
    @EnvironmentObject var gateway: GatewayClient
    @AppStorage("gatewayURL") private var gatewayURL = ""
    
    var body: some View {
        VStack(spacing: 20) {
            if gateway.isPairing {
                // Pairing in progress - show instructions
                PairingView()
            } else {
                // Normal connecting state
                ProgressView()
                    .scaleEffect(1.5)
                Text(gateway.statusText)
                    .foregroundColor(.secondary)
                
                if let error = gateway.lastError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding()
                    
                    Button("Retry") {
                        if let url = UserDefaults.standard.string(forKey: "gatewayURL"),
                           let token = UserDefaults.standard.string(forKey: "gatewayToken") {
                            gateway.connect(url: url, token: token)
                        }
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Change Settings") {
                        UserDefaults.standard.removeObject(forKey: "gatewayURL")
                        UserDefaults.standard.removeObject(forKey: "gatewayToken")
                    }
                    .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

struct PairingView: View {
    @EnvironmentObject var gateway: GatewayClient
    @AppStorage("gatewayURL") private var gatewayURL = ""
    
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: "iphone.and.arrow.forward")
                .font(.system(size: 48))
                .foregroundColor(.cyan)
                .frame(width: 80, height: 80)
                .background(Color.cyan.opacity(0.12))
                .clipShape(Circle())
            
            VStack(spacing: 8) {
                Text("Approve This Device")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("A pairing request has been sent.\nApprove it on your gateway to connect.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            // Progress indicator
            ProgressView()
                .scaleEffect(1.2)
            
            Text(gateway.statusText)
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                Text("On your gateway, run:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("openclaw nodes pending")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color(white: 0.15))
                        .cornerRadius(6)
                    
                    Spacer()
                }
                
                Text("Then approve with:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("openclaw nodes approve <id>")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color(white: 0.15))
                        .cornerRadius(6)
                    
                    Spacer()
                }
            }
            .padding()
            .background(Color(white: 0.1))
            .cornerRadius(12)
            .padding(.horizontal, 32)
            
            Spacer()
                .frame(height: 20)
            
            // Cancel button
            Button("Cancel") {
                gateway.cancelPairing()
                gatewayURL = ""
            }
            .foregroundColor(.red)
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environmentObject(GatewayClient())
        .environmentObject(SessionManager())
}
