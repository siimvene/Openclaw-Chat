import SwiftUI
import PhotosUI

// MARK: - iPad Layout (Simplified: Sessions + Chat only)

struct iPadChatLayout: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @State private var selectedSessionId: String?
    
    var body: some View {
        HStack(spacing: 0) {
            // Left: Sessions column
            iPadSessionsColumn(selectedSessionId: $selectedSessionId)
                .frame(width: 280)
            
            // Divider
            Rectangle()
                .fill(Color.glassBorder)
                .frame(width: 1)
            
            // Right: Chat view (always visible)
            iPadChatView()
        }
        .background(Color.appBackground)
    }
}

// MARK: - Sessions Column

struct iPadSessionsColumn: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var selectedSessionId: String?
    
    @State private var showNewSessionAlert = false
    @State private var newSessionName = ""
    @State private var showSettings = false
    @State private var editingSession: Session?
    @State private var renameText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with logo
            headerArea
            
            // Search bar
            searchBar
            
            // Sessions list with swipe actions
            sessionsList
            
            Spacer()
            
            // Bottom: Settings + New Chat
            bottomBar
        }
        .background(Color(red: 0.05, green: 0.07, blue: 0.10))
        .alert("New Session", isPresented: $showNewSessionAlert) {
            TextField("Session name", text: $newSessionName)
            Button("Create") { createSession() }
            Button("Cancel", role: .cancel) { newSessionName = "" }
        }
        .alert("Rename Session", isPresented: .init(
            get: { editingSession != nil },
            set: { if !$0 { editingSession = nil } }
        )) {
            TextField("Session name", text: $renameText)
            Button("Save") {
                if let session = editingSession {
                    sessionManager.renameSession(session, to: renameText)
                }
                editingSession = nil
            }
            Button("Cancel", role: .cancel) { editingSession = nil }
        }
        .fullScreenCover(isPresented: $showSettings) {
            iPadSettingsModal()
        }
    }
    
    // MARK: - Header
    private var headerArea: some View {
        HStack(spacing: 10) {
            // Logo - white circle with blue ring
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 32, height: 32)
                
                Image("Logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
            }
            .overlay(
                Circle()
                    .stroke(Color.appPrimary, lineWidth: 2)
            )
            
            Text("OpenClaw Chat")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Search Bar
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(Color.textMuted)
            
            TextField("Search sessions", text: $sessionManager.searchText)
                .font(.system(size: 13))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
    
    // MARK: - Sessions List with Swipe Actions
    private var sessionsList: some View {
        List {
            ForEach(sessionManager.filteredSessions) { session in
                iPadSessionRow(
                    session: session,
                    isSelected: session.id == sessionManager.activeSessionId
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .contentShape(Rectangle())
                .onTapGesture {
                    gateway.switchToSession(session.id)
                    sessionManager.selectSession(session)
                    selectedSessionId = session.id
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        sessionManager.deleteSession(session)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    
                    Button {
                        renameText = session.name
                        editingSession = session
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.appPrimary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - Bottom Bar (Settings + New Chat)
    private var bottomBar: some View {
        HStack(spacing: 10) {
            // Settings button
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16))
                    .foregroundColor(Color.textMuted)
                    .frame(width: 42, height: 42)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            
            // New Chat button
            Button {
                showNewSessionAlert = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("New Chat")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.appPrimary)
                .cornerRadius(10)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
    }
    
    private func createSession() {
        if sessionManager.activeSessionId != nil {
            gateway.saveCurrentSession()
        }
        let name = newSessionName.isEmpty ? nil : newSessionName
        let session = sessionManager.createSession(name: name)
        gateway.switchToSession(session.id)
        sessionManager.selectSession(session)
        selectedSessionId = session.id
        newSessionName = ""
    }
}

// MARK: - iPad Session Row

struct iPadSessionRow: View {
    let session: Session
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            // Chat icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appPrimary.opacity(0.15))
                    .frame(width: 34, height: 34)
                
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 13))
                    .foregroundColor(Color.appPrimary)
            }
            
            // Text
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(session.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(formatTime(session.lastMessageDate))
                        .font(.system(size: 10))
                        .foregroundColor(Color.textMuted)
                }
                
                if !session.lastMessage.isEmpty {
                    Text(session.lastMessage)
                        .font(.system(size: 11))
                        .foregroundColor(Color.textMuted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.appPrimary.opacity(0.15) : Color.clear)
        )
    }
    
    private func formatTime(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mma"
            return formatter.string(from: date).lowercased()
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }
    }
}

// MARK: - iPad Settings Modal (Full Screen)

struct iPadSettingsModal: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @AppStorage("gatewayURL") private var gatewayURL = ""
    @AppStorage("gatewayToken") private var gatewayToken = ""
    @AppStorage("chatTextSize") private var chatTextSize: Double = 14
    @State private var showLogoutConfirm = false
    @State private var showWipeConfirm = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    settingsSection("Connection") {
                        settingsRow(
                            icon: "circle.fill",
                            iconColor: gateway.isConnected ? .onlineGreen : .red,
                            label: "Settings",
                            value: gateway.isConnected ? "Connected" : "Disconnected"
                        )
                        settingsDivider
                        settingsRow(icon: "network", label: "Gateway", value: gatewayURL.isEmpty ? "Not set" : gatewayURL)
                        settingsDivider
                        settingsRow(icon: "clock", label: "Uptime", value: formatUptime(gateway.uptimeMs / 1000))
                        if gateway.serverVersion != "dev" && gateway.serverVersion != "Unknown" {
                            settingsDivider
                            settingsRow(icon: "tag", label: "Server Version", value: gateway.serverVersion)
                        }
                        if !gateway.activeModel.isEmpty {
                            settingsDivider
                            settingsRow(icon: "cpu", label: "Model", value: gateway.activeModel)
                        }
                    }
                    
                    settingsSection("Appearance") {
                        HStack {
                            Label("Text Size", systemImage: "textformat.size")
                                .foregroundColor(.white)
                            Spacer()
                            Text("\(Int(chatTextSize))pt")
                                .foregroundColor(Color.textMuted)
                        }
                        Slider(value: $chatTextSize, in: 12...20, step: 1)
                            .tint(.appPrimary)
                    }
                    
                    settingsSection("Security") {
                        NavigationLink {
                            SecurityView(gateway: gateway, selectedTab: .constant(0))
                                .environmentObject(gateway)
                                .environmentObject(sessionManager)
                        } label: {
                            HStack {
                                Label("Security Audit", systemImage: "shield.checkered")
                                    .foregroundColor(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(Color.textMuted)
                            }
                        }
                    }
                    
                    settingsSection("About") {
                        settingsRow(icon: "app.badge", label: "App Version", value: appVersion)
                        settingsDivider
                        settingsRow(icon: "rectangle.stack", label: "Active Session", value: gateway.activeSessionKey)
                    }
                    
                    settingsSection("Actions") {
                        Button("Clear Device Data", role: .destructive) {
                            showWipeConfirm = true
                        }
                        settingsDivider
                        Button("Log Out") {
                            showLogoutConfirm = true
                        }
                        .foregroundColor(.red)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
            .background(Color.appBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("Log Out", isPresented: $showLogoutConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Log Out", role: .destructive) {
                    gateway.disconnect()
                    gatewayURL = ""
                    gatewayToken = ""
                    dismiss()
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
        }
    }
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }
    
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color.textMuted)
                .padding(.horizontal, 4)
            
            VStack(spacing: 10) {
                content()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
    }
    
    private func settingsRow(icon: String, iconColor: Color = .secondary, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(iconColor)
                .frame(width: 20)
            Text(label)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(Color.textMuted)
        }
    }
    
    private var settingsDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
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

// MARK: - iPad Chat View

struct iPadChatView: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @AppStorage("chatTextSize") private var chatTextSize: Double = 14
    @State private var fullscreenImage: UIImage?
    @State private var showFullscreenImage = false
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    @State private var showingAttachmentOptions = false
    @State private var showingPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingImageData: Data?
    @State private var pendingImagePreview: UIImage?
    
    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImageData != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            chatHeader
            
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        Text("TODAY")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.textMuted)
                            .padding(.vertical, 8)
                        
                        ForEach(gateway.messages) { message in
                            iPadMessageBubble(message: message) { image in
                                fullscreenImage = image
                                showFullscreenImage = true
                            }
                                .id(message.id)
                        }
                        
                        if gateway.isTyping {
                            iPadTypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .onChange(of: gateway.messages.count) { scrollToBottom(proxy: proxy) }
                .onChange(of: gateway.isTyping) { scrollToBottom(proxy: proxy) }
            }
            
            // Input area
            chatInputArea
        }
        .background(Color.appBackground)
        .fullScreenCover(isPresented: $showFullscreenImage) {
            if let image = fullscreenImage {
                ZStack {
                    Color.black.ignoresSafeArea()
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
                .onTapGesture {
                    showFullscreenImage = false
                    fullscreenImage = nil
                }
            }
        }
    }
    
    private var chatHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(gateway.isConnected ? Color.onlineGreen : Color.gray)
                .frame(width: 8, height: 8)
            
            Text(sessionManager.activeSession?.name ?? "General")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
            
            Text("- \(gateway.isConnected ? "Online" : "Offline")")
                .font(.system(size: 14))
                .foregroundColor(Color.textMuted)
            
            if !gateway.activeModel.isEmpty {
                Text(gateway.activeModel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.textMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.08))
                    )
            }
            
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.appBackground)
        .overlay(
            Rectangle().fill(Color.glassBorder).frame(height: 1),
            alignment: .bottom
        )
    }
    
    // Input with mic inside, transforms to send button when typing
    private var chatInputArea: some View {
        VStack(spacing: 8) {
            // Image preview if pending
            if let preview = pendingImagePreview {
                HStack {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            Button { clearPendingImage() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .offset(x: 6, y: -6),
                            alignment: .topTrailing
                        )
                    Spacer()
                }
                .padding(.horizontal, 18)
            }
            
            HStack(spacing: 12) {
                // Attachment
                Button { showingAttachmentOptions = true } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 18))
                        .foregroundColor(Color.textMuted)
                }
                
                // Input field with mic/send inside
                HStack(spacing: 8) {
                    TextField("Message OpenClaw...", text: $inputText, axis: .vertical)
                        .font(.system(size: chatTextSize))
                        .foregroundColor(.white)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .onSubmit { sendMessage() }
                    
                    // Mic or Send button (inside the field)
                    if canSend {
                        Button { sendMessage() } label: {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(Color.appPrimary)
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        Button { } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color.textMuted)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: canSend)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(isInputFocused ? Color.appPrimary.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Color.appBackground)
        .overlay(
            Rectangle().fill(Color.glassBorder).frame(height: 1),
            alignment: .top
        )
        .confirmationDialog("Add Attachment", isPresented: $showingAttachmentOptions) {
            Button("Photo Library") { showingPhotoPicker = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { await loadSelectedPhoto(newItem) }
        }
    }
    
    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    pendingImageData = data
                    pendingImagePreview = UIImage(data: data)
                    selectedPhotoItem = nil
                }
            }
        } catch {
            print("Failed to load image: \(error)")
        }
    }
    
    private func clearPendingImage() {
        pendingImageData = nil
        pendingImagePreview = nil
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let imageData = pendingImageData {
            gateway.sendMessageWithImage(text.isEmpty ? "What's in this image?" : text, imageData: imageData)
            clearPendingImage()
            inputText = ""
        } else {
            guard !text.isEmpty else { return }
            inputText = ""
            gateway.sendMessage(text)
        }
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if gateway.isTyping {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = gateway.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - iPad Message Bubble

struct iPadMessageBubble: View {
    let message: ChatMessage
    let onImageTap: (UIImage) -> Void
    @AppStorage("chatTextSize") private var chatTextSize: Double = 14
    
    private var isUser: Bool { message.role == .user }
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isUser { Spacer(minLength: 60) }
            
            if !isUser {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.appPrimary)
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                }
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleContent
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isUser ? Color.appPrimary : Color.white.opacity(0.08))
                    )
                    .contextMenu {
                        Button { UIPasteboard.general.string = message.content } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                
                HStack(spacing: 4) {
                    Text(isUser ? "YOU" : "AI ASSISTANT")
                        .font(.system(size: 9, weight: .medium))
                    Text("•")
                        .font(.system(size: 9))
                    Text(formatTime(message.timestamp))
                        .font(.system(size: 9))
                }
                .foregroundColor(Color.textMuted)
            }
            
            if isUser {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color.textMuted)
                    )
            }
            
            if !isUser { Spacer(minLength: 60) }
        }
    }
    
    @ViewBuilder
    private var bubbleContent: some View {
        if let image = message.image {
            VStack(alignment: .leading, spacing: 6) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture { onImageTap(image) }
                
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: chatTextSize))
                        .foregroundColor(.white)
                }
            }
            .padding(10)
        } else {
            Text(message.content)
                .font(.system(size: chatTextSize))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

// MARK: - iPad Typing Indicator

struct iPadTypingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appPrimary)
                    .frame(width: 28, height: 28)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
            }
            
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.textMuted)
                        .frame(width: 5, height: 5)
                        .offset(y: animating ? -2 : 2)
                        .animation(
                            .easeInOut(duration: 0.35)
                                .repeatForever()
                                .delay(Double(i) * 0.1),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.08))
            )
            
            Spacer()
        }
        .onAppear { animating = true }
    }
}

#Preview {
    iPadChatLayout()
        .environmentObject(GatewayClient())
        .environmentObject(SessionManager())
}
