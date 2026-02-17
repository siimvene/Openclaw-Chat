import SwiftUI

struct ChatView: View {
    @EnvironmentObject var gateway: GatewayClient
    @EnvironmentObject var sessionManager: SessionManager
    @Binding var selectedTab: Int
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showSettings = false
    @State private var keyboardHeight: CGFloat = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Messages
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
                .defaultScrollAnchor(.bottom)
                .contentShape(Rectangle())
                .onTapGesture {
                    isInputFocused = false
                }
                .onChange(of: gateway.messages.count) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: gateway.isTyping) {
                    scrollToBottom(proxy: proxy)
                }
                .onChange(of: keyboardHeight) { _, _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToBottom(proxy: proxy)
                    }
                }
            }
            
            // Input area with keyboard offset
            inputArea
            
            // Keyboard spacer
            Color.clear
                .frame(height: keyboardHeight)
        }
        .background(Color.black)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                    // Keyboard height minus tab bar and safe area
                    keyboardHeight = max(0, frame.height - 85)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
                keyboardHeight = 0
            }
        }
    }
    
    private var header: some View {
        HStack {
            Button {
                selectedTab = 0 // Go to Sessions
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
            
            // Clear chat button
            if !gateway.messages.isEmpty {
                Button {
                    gateway.clearMessages()
                } label: {
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
        HStack(spacing: 8) {
            VoiceButton { transcribedText in
                inputText = transcribedText
                sendMessage()
            }
            
            HStack {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .focused($isInputFocused)
                    .onSubmit(sendMessage)
                
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                        .foregroundColor(inputText.isEmpty ? .gray : .blue)
                }
                .disabled(inputText.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(white: 0.15))
            .cornerRadius(20)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.1))
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        inputText = ""
        gateway.sendMessage(text)
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
    
    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleColor)
                    .foregroundColor(.white)
                    .cornerRadius(18)
                
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
