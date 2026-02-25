import SwiftUI

struct VoiceView: View {
    @EnvironmentObject var gateway: GatewayClient
    @StateObject private var voice = VoiceInput()
    @StateObject private var ttsStreamer = TTSStreamer()
    @State private var voiceHistory: [VoiceExchange] = []
    @State private var isWaitingForResponse = false
    @State private var currentResponse = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                conversationArea
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                inputArea
            }
            .background(Color.black)
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear {
                // Set up auto-send callback for when voice auto-stops after silence
                ttsStreamer.connect()
                voice.onFinalTranscription = { text in
                    sendVoiceMessage(text)
                }
            }
            .onChange(of: gateway.isTyping) { oldVal, newVal in
                handleTypingChange(newVal)
            }
            .onChange(of: gateway.voiceResponse) { _, _ in
                handleVoiceResponseChange()
            }
            .alert("Voice Error", isPresented: hasError) {
                Button("OK") { voice.errorMessage = nil }
            } message: {
                Text(voice.errorMessage ?? "")
            }
        }
    }
    
    private var hasError: Binding<Bool> {
        Binding(
            get: { voice.errorMessage != nil },
            set: { if !$0 { voice.errorMessage = nil } }
        )
    }
    
    // MARK: - Conversation Area
    
    private var conversationArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(voiceHistory) { exchange in
                        VoiceExchangeView(exchange: exchange)
                    }
                    
                    pendingResponseView
                        .id("bottom")
                }
                .padding(.vertical)
            }
            .onChange(of: voiceHistory.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: currentResponse) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
    
    @ViewBuilder
    private var pendingResponseView: some View {
        if isWaitingForResponse && currentResponse.isEmpty {
            HStack(spacing: 8) {
                ProgressView().tint(.purple)
                Text("Thinking...").foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        } else if !currentResponse.isEmpty {
            Text(currentResponse)
                .padding()
                .background(Color.purple.opacity(0.15))
                .cornerRadius(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Input Area
    
    private var inputArea: some View {
        VStack(spacing: 12) {
            statusRow
            recordButton
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(white: 0.08))
    }
    
    private var statusRow: some View {
        HStack(spacing: 16) {
            VoiceOrbMini(
                isRecording: voice.isRecording,
                isSpeaking: voice.isSpeaking,
                audioLevel: voice.audioLevel
            )
            .frame(width: 60, height: 60)
            
            statusLabel
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if voice.isSpeaking {
                stopSpeakingButton
            }
        }
        .padding(.horizontal)
    }
    
    @ViewBuilder
    private var statusLabel: some View {
        if voice.isSpeaking {
            Label("Speaking...", systemImage: "speaker.wave.2.fill")
                .foregroundColor(.purple)
                .font(.subheadline)
        } else if voice.isRecording {
            if voice.transcription.isEmpty {
                Label("Listening...", systemImage: "ear.fill")
                    .foregroundColor(.red)
                    .font(.subheadline)
            } else {
                Text(voice.transcription)
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
        } else if !voice.isAuthorized {
            Label("Microphone access required", systemImage: "mic.slash")
                .foregroundColor(.orange)
                .font(.subheadline)
        } else {
            Label("Tap to speak", systemImage: "mic")
                .foregroundColor(.secondary)
                .font(.subheadline)
        }
    }
    
    private var stopSpeakingButton: some View {
        Button { voice.stopSpeaking() } label: {
            Image(systemName: "speaker.slash.fill")
                .font(.title3)
                .foregroundColor(.purple)
                .frame(width: 44, height: 44)
                .background(Color.purple.opacity(0.2))
                .clipShape(Circle())
        }
    }
    
    private var recordButton: some View {
        Button { handleRecordButton() } label: {
            ZStack {
                Circle()
                    .fill(voice.isRecording ? Color.red : Color.blue)
                    .frame(width: 72, height: 72)
                
                if voice.isRecording {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
        }
        .disabled(!voice.isAuthorized || voice.isSpeaking)
        .opacity(voice.isAuthorized && !voice.isSpeaking ? 1.0 : 0.4)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if !voiceHistory.isEmpty {
                Button { voiceHistory.removeAll() } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleRecordButton() {
        if voice.isRecording {
            let text = voice.stopRecording()
            if !text.isEmpty {
                sendVoiceMessage(text)
            }
        } else {
            voice.startRecording()
        }
    }
    
    private func sendVoiceMessage(_ text: String) {
        let exchange = VoiceExchange(userMessage: text, assistantMessage: nil)
        voiceHistory.append(exchange)
        isWaitingForResponse = true
        currentResponse = ""
        // Add voice context hint so agent responds conversationally
        let voiceHint = "[Voice message - respond naturally and conversationally, keep response concise for speech] "
        gateway.sendVoiceMessage(voiceHint + text)
    }
    
    private func handleTypingChange(_ isTyping: Bool) {
        // Only process if we're waiting for a response from a voice interaction
        guard isWaitingForResponse else { return }
        
        if !isTyping {
            // Typing stopped - finalize after a short delay to ensure we have full content
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.checkAndFinalizeResponse()
            }
        }
    }
    
    private func handleVoiceResponseChange() {
        // Only process if we're waiting for a response from a voice interaction
        guard isWaitingForResponse else { return }
        
        // Update currentResponse for display (streaming)
        currentResponse = gateway.voiceResponse
    }
    
    private func checkAndFinalizeResponse() {
        // Only finalize if typing has actually stopped
        guard !gateway.isTyping else { return }
        guard isWaitingForResponse else { return }
        
        let content = gateway.voiceResponse
        guard !content.isEmpty else { return }
        
        finalizeResponse(content)
    }
    
    private func finalizeResponse(_ content: String) {
        isWaitingForResponse = false
        
        if !voiceHistory.isEmpty {
            voiceHistory[voiceHistory.count - 1].assistantMessage = content
        }
        
        currentResponse = ""
        
        // Only speak if content is meaningful (more than just a few chars)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3 else {
            print("[Voice] Skipping TTS for very short response: \(trimmed)")
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.ttsStreamer.streamSpeech(content)
        }
    }
    
    // MARK: - Server-side TTS
    
    private func speakWithServerTTS(_ content: String) {
        Task {
            if let audioData = await gateway.convertToSpeech(content) {
                print("[VoiceView] Using server-side TTS")
                await MainActor.run {
                    voice.playServerAudio(audioData)
                }
            } else {
                print("[VoiceView] Falling back to local TTS")
                await MainActor.run {
                    voice.speak(content)
                }
            }
        }
    }
}

// MARK: - Voice Exchange Model

struct VoiceExchange: Identifiable {
    let id = UUID()
    let userMessage: String
    var assistantMessage: String?
    let timestamp = Date()
}

// MARK: - Voice Exchange View

struct VoiceExchangeView: View {
    let exchange: VoiceExchange
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // User message
            HStack {
                Spacer()
                Text(exchange.userMessage)
                    .padding(12)
                    .background(Color.blue.opacity(0.3))
                    .cornerRadius(16)
                    .foregroundColor(.white)
            }
            
            // Assistant response
            if let response = exchange.assistantMessage {
                HStack {
                    Text(response)
                        .padding(12)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(16)
                        .foregroundColor(.white)
                    Spacer()
                }
            }
        }
        .padding(.horizontal)
    }
}

// MARK: - Mini Voice Orb

struct VoiceOrbMini: View {
    let isRecording: Bool
    let isSpeaking: Bool
    let audioLevel: Float
    
    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(orbColor.opacity(0.3), lineWidth: 2)
                .scaleEffect(isActive ? 1.0 + CGFloat(audioLevel) * 0.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: audioLevel)
            
            // Core
            Circle()
                .fill(
                    RadialGradient(
                        colors: [orbColor.opacity(0.8), orbColor.opacity(0.3)],
                        center: .center,
                        startRadius: 5,
                        endRadius: 25
                    )
                )
                .frame(width: 40, height: 40)
            
            // Icon
            if !isActive {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
            } else if isSpeaking {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }
        }
    }
    
    private var isActive: Bool { isRecording || isSpeaking }
    
    private var orbColor: Color {
        if isSpeaking { return .purple }
        if isRecording { return .red }
        return .blue
    }
}

// MARK: - Voice Orb

struct VoiceOrb: View {
    let isRecording: Bool
    let isSpeaking: Bool
    let audioLevel: Float
    
    @State private var phase: CGFloat = 0
    @State private var innerPulse: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Outer glow rings
            ForEach(0..<3) { i in
                Circle()
                    .stroke(
                        orbColor.opacity(0.1 - Double(i) * 0.03),
                        lineWidth: 2
                    )
                    .frame(
                        width: 160 + CGFloat(i) * 40 + CGFloat(audioLevel) * 20,
                        height: 160 + CGFloat(i) * 40 + CGFloat(audioLevel) * 20
                    )
                    .scaleEffect(isActive ? 1.0 + CGFloat(audioLevel) * 0.15 : 0.95)
                    .animation(
                        .easeInOut(duration: 0.8 + Double(i) * 0.2)
                        .repeatForever(autoreverses: true),
                        value: isActive
                    )
            }
            
            // Waveform ring
            if isActive {
                WaveformRing(
                    audioLevel: audioLevel,
                    phase: phase,
                    color: orbColor
                )
                .frame(width: 180, height: 180)
            }
            
            // Core orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            orbColor.opacity(0.8),
                            orbColor.opacity(0.4),
                            orbColor.opacity(0.1)
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 70
                    )
                )
                .frame(width: 140, height: 140)
                .scaleEffect(innerPulse)
            
            // Inner bright core
            Circle()
                .fill(orbColor.opacity(0.6))
                .frame(width: 60, height: 60)
                .blur(radius: 8)
                .scaleEffect(1.0 + CGFloat(audioLevel) * 0.4)
            
            // Center icon
            if !isActive {
                Image(systemName: "mic.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                innerPulse = 1.05
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                startWaveAnimation()
            }
        }
        .onChange(of: isSpeaking) { _, speaking in
            if speaking {
                startWaveAnimation()
            }
        }
    }
    
    private var isActive: Bool {
        isRecording || isSpeaking
    }
    
    private var orbColor: Color {
        if isSpeaking { return .purple }
        if isRecording { return .red }
        return .blue
    }
    
    private func startWaveAnimation() {
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            phase = .pi * 2
        }
    }
}

// MARK: - Waveform Ring

struct WaveformRing: View {
    let audioLevel: Float
    let phase: CGFloat
    let color: Color
    
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius: CGFloat = min(size.width, size.height) / 2 - 10
            let points = 64
            
            var path = Path()
            for i in 0..<points {
                let angle = CGFloat(i) / CGFloat(points) * .pi * 2
                let wave = sin(angle * 4 + phase) * CGFloat(audioLevel) * 12
                let r = radius + wave
                let x = center.x + cos(angle) * r
                let y = center.y + sin(angle) * r
                
                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
            path.closeSubpath()
            
            context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 2)
        }
    }
}

// MARK: - Voice Button (compact, for ChatView)

struct VoiceButton: View {
    @StateObject private var voice = VoiceInput()
    let onTranscription: (String) -> Void
    
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: toggleRecording) {
            ZStack {
                if voice.isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .scaleEffect(pulseScale)
                        .frame(width: 44, height: 44)
                }
                
                Image(systemName: voice.isRecording ? "mic.fill" : "mic")
                    .font(.title2)
                    .foregroundColor(voice.isRecording ? .red : .blue)
                    .frame(width: 44, height: 44)
            }
        }
        .disabled(!voice.isAuthorized)
        .opacity(voice.isAuthorized ? 1.0 : 0.4)
        .onAppear {
            voice.onFinalTranscription = { text in
                onTranscription(text)
            }
        }
        .onChange(of: voice.isRecording) { _, recording in
            if recording {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulseScale = 1.3
                }
            } else {
                withAnimation(.easeOut(duration: 0.2)) {
                    pulseScale = 1.0
                }
            }
        }
    }
    
    private func toggleRecording() {
        if voice.isRecording {
            let text = voice.stopRecording()
            if !text.isEmpty {
                onTranscription(text)
            }
        } else {
            voice.startRecording()
        }
    }
}
