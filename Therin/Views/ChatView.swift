import SwiftUI
import PhotosUI

struct ChatView: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var selectedTab: Int
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
                    LazyVStack(spacing: 8) {
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
                    // Scroll to bottom when view loads with existing messages
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToBottom(proxy: proxy)
                    }
                }
                .onChange(of: gateway.messages.count) { scrollToBottom(proxy: proxy) }
                .onChange(of: gateway.messages.last?.content) { _, _ in
                    // Scroll during streaming as message grows
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: gateway.isTyping) { scrollToBottom(proxy: proxy) }
                .onChange(of: keyboardHeight) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { scrollToBottom(proxy: proxy) }
                }
                .onChange(of: inputText) { _, newText in
                    if newText.contains("\n") || newText.count > 60 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { scrollToBottom(proxy: proxy) }
                    }
                }
                .onChange(of: scrollTrigger) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { scrollToBottom(proxy: proxy) }
                }
            }
            
            inputArea
            Color.clear.frame(height: keyboardHeight)
        }
        .background(Color.black)
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
    
    private var header: some View {
        HStack {
            Button {
                selectedTab = 0
            } label: {
                HStack(spacing: 10) {
                    Image("Logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sessionManager.activeSession?.name ?? "OpenClaw")
                            .font(.headline)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(gateway.isConnected ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(gateway.isConnected ? "Online" : "Offline")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            if !gateway.messages.isEmpty {
                Button { gateway.clearMessages() } label: {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding(.trailing, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(white: 0.1))
    }
    
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
            
            HStack(spacing: 8) {
                Button { showingAttachmentOptions = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title)
                        .foregroundColor(.gray)
                }
                .confirmationDialog("Add Attachment", isPresented: $showingAttachmentOptions) {
                    Button("Photo Library") { showingPhotoPicker = true }
                    Button("Take Photo") { showingCamera = true }
                    Button("Cancel", role: .cancel) {}
                }
                
                HStack {
                    TextField("Message", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...5)
                        .focused($isInputFocused)
                        .onSubmit(sendMessage)
                    
                    if canSend {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title)
                                .foregroundColor(.blue)
                        }
                        .transition(.scale.combined(with: .opacity))
                    } else {
                        VoiceButton { transcribedText in
                            inputText = transcribedText
                            sendMessage()
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: canSend)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.15))
                .cornerRadius(20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(white: 0.1))
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
        // Double scroll to handle race conditions
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

struct MessageBubble: View {
    let message: ChatMessage
    @State private var showFullscreen = false
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
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
                                .font(.body)
                        }
                    }
                    .padding(8)
                    .background(bubbleColor)
                    .cornerRadius(18)
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
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(bubbleColor)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                        .contextMenu {
                            Button { UIPasteboard.general.string = message.content } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                }
                
                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            if message.role == .assistant || message.role == .system { Spacer(minLength: 60) }
        }
    }
    
    private var bubbleColor: Color {
        switch message.role {
        case .user: return .blue
        case .assistant: return Color(white: 0.2)
        case .system: return .orange.opacity(0.3)
        }
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
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.gray)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(white: 0.2))
            .cornerRadius(18)
            
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
