import SwiftUI
import PhotosUI

struct ChatView: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var selectedTab: Int
    @AppStorage("chatTextSize") private var chatTextSize: Double = 14
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showSettings = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var scrollTrigger = false

    
    // Photo/Camera state
    @State private var showingAttachmentOptions = false
    @State private var showingPhotoPicker = false
    @State private var showingCamera = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pendingImageData: Data?
    @State private var pendingImagePreview: UIImage?
    
    var body: some View {
        VStack(spacing: 0) {
            header
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        // Date divider
                        DateDivider(text: "Today")
                        
                        ForEach(gateway.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if gateway.isTyping {
                            TypingIndicator()
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture { isInputFocused = false }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onChange(of: gateway.messages.count) { scrollToBottom(proxy: proxy) }
                .onChange(of: gateway.messages.last?.content) { _, _ in
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: gateway.isTyping) { scrollToBottom(proxy: proxy) }
                .onChange(of: keyboardHeight) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { scrollToBottom(proxy: proxy) }
                }
                .onChange(of: scrollTrigger) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { scrollToBottom(proxy: proxy) }
                }
            }
            
            inputArea
            Color.clear.frame(height: keyboardHeight)
        }
        .background(Color.appBackground)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    keyboardHeight = max(0, frame.height - 85)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { keyboardHeight = 0 }
        }
    }
    
    // MARK: - Header (Glass Panel)
    private var header: some View {
        HStack {
            Button {
                selectedTab = 0
            } label: {
                HStack(spacing: 12) {
                    // Avatar with online indicator
                    ZStack(alignment: .bottomTrailing) {
                        Image("Logo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 40, height: 40)
                            .background(Color.appPrimary.opacity(0.2))
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.appPrimary.opacity(0.3), lineWidth: 1))
                        
                        // Online dot
                        Circle()
                            .fill(gateway.isConnected ? Color.onlineGreen : Color.gray)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.appBackground, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionManager.activeSession?.name ?? "General Chat")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(gateway.isConnected ? "Online • \(gateway.activeModel.isEmpty ? "OpenClaw AI" : gateway.activeModel)" : "Offline")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.textMuted)
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Search button
            Button { } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20))
                    .foregroundColor(Color.textMuted)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
            
            // More button
            Button { gateway.clearMessages() } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20))
                    .foregroundColor(Color.textMuted)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.05))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 48)
        .padding(.bottom, 16)
        .background(
            Rectangle()
                .fill(.regularMaterial.opacity(0.5))
                .background(Color.glassFill)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.glassBorder), alignment: .bottom)
        )
    }
    
    // MARK: - Input Area (Glass Panel)
    private var inputArea: some View {
        VStack(spacing: 8) {
            if let preview = pendingImagePreview {
                HStack {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            Button { clearPendingImage() } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .offset(x: 8, y: -8),
                            alignment: .topTrailing
                        )
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            
            HStack(spacing: 12) {
                // Attachment button (plus)
                Button { showingAttachmentOptions = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color.textMuted)
                }
                
                // Input field with mic inside
                HStack(spacing: 8) {
                    TextField("Type a message...", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: chatTextSize))
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .foregroundColor(.white)
                    
                    // Mic button (when not sending)
                    if !canSend {
                        VoiceButton { transcribedText in
                            inputText = transcribedText
                            sendMessage()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: canSend)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(isInputFocused ? Color.white.opacity(0.1) : Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(isInputFocused ? Color.appPrimary.opacity(0.5) : Color.glassBorder, lineWidth: 1)
                        )
                )
                .animation(.easeInOut(duration: 0.2), value: isInputFocused)
                
                // Send button (separate, matching mockup)
                if canSend {
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.appPrimary)
                            .clipShape(Circle())
                            .shadow(color: Color.appPrimary.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.15), value: canSend)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(
            Rectangle()
                .fill(.regularMaterial.opacity(0.5))
                .background(Color.glassFill)
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.glassBorder), alignment: .top)
        )
        .confirmationDialog("Add Attachment", isPresented: $showingAttachmentOptions) {
            Button("Photo Library") { showingPhotoPicker = true }
            Button("Take Photo") { showingCamera = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showingPhotoPicker, selection: $selectedPhotoItem, matching: .images)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task { await loadSelectedPhoto(newItem) }
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraView { imageData in
                if let data = imageData, let image = UIImage(data: data) {
                    pendingImageData = data
                    pendingImagePreview = image
                }
            }
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImageData != nil
    }
    
    private func clearPendingImage() {
        pendingImageData = nil
        pendingImagePreview = nil
        selectedPhotoItem = nil
    }
    
    private func loadSelectedPhoto(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    pendingImageData = data
                    if let image = UIImage(data: data) { pendingImagePreview = image }
                }
            }
        } catch {
            print("[ChatView] Failed to load photo: \(error)")
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImageData != nil else { return }
        
        let message = text.isEmpty ? "Analyze this image" : text
        
        if let imageData = pendingImageData {
            inputText = ""
            clearPendingImage()
            gateway.sendMessageWithImage(message, imageData: imageData)
        } else {
            inputText = ""
            gateway.sendMessage(message)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { scrollTrigger.toggle() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scrollTrigger.toggle() }
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

// MARK: - Date Divider
struct DateDivider: View {
    let text: String
    
    var body: some View {
        HStack {
            Spacer()
            Text(text.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                )
            Spacer()
        }
    }
}

// MARK: - Message Bubble with Avatar
struct MessageBubble: View {
    let message: ChatMessage
    @AppStorage("chatTextSize") private var chatTextSize: Double = 14
    @State private var showFullscreen = false
    
    private var isUser: Bool { message.role == .user }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 40) }
            
            // AI Avatar (left side)
            if !isUser {
                avatarView
            }
            
            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleContent
                
                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(Color.textMuted)
                    .padding(.horizontal, 4)
            }
            
            // User Avatar (right side)
            if isUser {
                userAvatarView
            }
            
            if !isUser { Spacer(minLength: 40) }
        }
    }
    
    private var avatarView: some View {
        Image("Logo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 32, height: 32)
            .background(Color.appPrimary.opacity(0.1))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.appPrimary.opacity(0.2), lineWidth: 1))
    }
    
    private var userAvatarView: some View {
        Circle()
            .fill(Color.white.opacity(0.1))
            .frame(width: 32, height: 32)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color.textMuted)
            )
            .overlay(Circle().stroke(Color.glassBorder, lineWidth: 1))
    }
    
    @ViewBuilder
    private var bubbleContent: some View {
        if let image = message.image {
            VStack(alignment: .leading, spacing: 6) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: 200, maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .onTapGesture { showFullscreen = true }
                
                if !message.content.isEmpty {
                    Text(message.content)
                        .foregroundColor(.white)
                        .font(.system(size: chatTextSize))
                }
            }
            .padding(10)
            .background(bubbleBackground)
            .clipShape(bubbleShape)
            .messageShadow()
            .contextMenu {
                Button { UIPasteboard.general.string = message.content } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
                Button { UIPasteboard.general.image = image } label: {
                    Label("Copy Image", systemImage: "photo.on.rectangle")
                }
            }
            .fullScreenCover(isPresented: $showFullscreen) {
                FullscreenImageView(image: image, isPresented: $showFullscreen)
            }
        } else {
            Text(message.content)
                .font(.system(size: chatTextSize))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(bubbleBackground)
                .clipShape(bubbleShape)
                .messageShadow()
                .contextMenu {
                    Button { UIPasteboard.general.string = message.content } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                }
        }
    }
    
    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            Color.appPrimary
        } else {
            // Glass panel for AI messages
            ZStack {
                Color.white.opacity(0.03)
                Rectangle().fill(.ultraThinMaterial.opacity(0.2))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
        }
    }
    
    private var bubbleShape: some Shape {
        BubbleShape(isUser: isUser)
    }
}

// Custom bubble shape with one flat corner
struct BubbleShape: Shape {
    let isUser: Bool
    
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let smallRadius: CGFloat = 4
        var path = Path()
        
        if isUser {
            // User: flat bottom-right corner
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - smallRadius))
            path.addArc(center: CGPoint(x: rect.maxX - smallRadius, y: rect.maxY - smallRadius), radius: smallRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // AI: flat bottom-left corner
            path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addArc(center: CGPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + smallRadius, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + smallRadius, y: rect.maxY - smallRadius), radius: smallRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
            path.addArc(center: CGPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        
        return path
    }
}

struct FullscreenImageView: View {
    let image: UIImage
    @Binding var isPresented: Bool
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in scale = lastScale * value }
                        .onEnded { _ in
                            lastScale = scale
                            if scale < 1.0 {
                                withAnimation { scale = 1.0 }
                                lastScale = 1.0
                            }
                        }
                )
                .onTapGesture(count: 2) {
                    withAnimation {
                        if scale > 1.0 { scale = 1.0; lastScale = 1.0 }
                        else { scale = 2.0; lastScale = 2.0 }
                    }
                }
            
            Button { isPresented = false } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(20)
            }
        }
    }
}


struct TypingIndicator: View {
    @State private var animating = false
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Avatar
            Image("Logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)
                .background(Color.appPrimary.opacity(0.1))
                .clipShape(Circle())
            
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.textMuted)
                        .frame(width: 8, height: 8)
                        .offset(y: animating ? -4 : 4)
                        .animation(
                            .easeInOut(duration: 0.4)
                                .repeatForever()
                                .delay(Double(i) * 0.15),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    Color.white.opacity(0.03)
                    Rectangle().fill(.ultraThinMaterial.opacity(0.2))
                }
            )
            .clipShape(BubbleShape(isUser: false))
            .overlay(
                BubbleShape(isUser: false)
                    .stroke(Color.glassBorder, lineWidth: 1)
            )
            
            Spacer()
        }
        .onAppear { animating = true }
    }
}

#Preview {
    ChatView(selectedTab: .constant(1))
        .environmentObject(GatewayClient())
        .environmentObject(SessionManager())
}
