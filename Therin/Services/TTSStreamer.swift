import Foundation
import AVFoundation

@MainActor
class TTSStreamer: ObservableObject {
    @Published var isPlaying = false
    @Published var isConnected = false
    
    private var webSocket: URLSessionWebSocketTask?
    private var audioPlayer: AVAudioPlayer?
    private var audioBuffer = Data()
    private var isStreaming = false
    private var streamStartTime: Date?
    private var pendingText: String?  // For fallback
    
    // Local TTS fallback
    private let synthesizer = AVSpeechSynthesizer()
    
    private let baseURL: String
    
    init(baseURL: String = "wss://gateway.yubimgr.io/tts/") {
        self.baseURL = baseURL
    }
    
    func connect() {
        guard let url = URL(string: baseURL) else { 
            isConnected = false
            return 
        }
        
        let session = URLSession(configuration: .default)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()
        isConnected = true
        
        receiveMessage()
        print("[TTS] Connected")
    }
    
    func disconnect() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        isConnected = false
    }
    
    func streamSpeech(_ text: String) {
        pendingText = text  // Save for fallback
        
        // If not connected or connection fails, use local TTS
        guard isConnected else {
            connect()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if self.isConnected {
                    self.streamSpeech(text)
                } else {
                    print("[TTS] Server unavailable, using local TTS")
                    self.speakLocal(text)
                }
            }
            return
        }
        
        audioBuffer = Data()
        isStreaming = true
        streamStartTime = Date()
        
        let request: [String: Any] = [
            "method": "tts.stream",
            "id": UUID().uuidString,
            "params": ["text": text]
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: request),
           let str = String(data: data, encoding: .utf8) {
            webSocket?.send(.string(str)) { [weak self] error in
                if let error = error {
                    print("[TTS] Send error: \(error), falling back to local")
                    Task { @MainActor in
                        self?.speakLocal(text)
                    }
                }
            }
        }
        
        // Timeout fallback - if no audio received in 5 seconds, use local
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self = self, self.isStreaming, self.audioBuffer.isEmpty else { return }
            print("[TTS] Timeout waiting for server, using local TTS")
            self.isStreaming = false
            if let text = self.pendingText {
                self.speakLocal(text)
            }
        }
    }
    
    private func receiveMessage() {
        webSocket?.receive { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self?.handleMessage(message)
                    self?.receiveMessage()
                case .failure(let error):
                    print("[TTS] Receive error: \(error)")
                    self?.isConnected = false
                    // Fallback on connection error
                    if let text = self?.pendingText, self?.isStreaming == true {
                        self?.speakLocal(text)
                    }
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            if let data = text.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let type = json["type"] as? String {
                
                switch type {
                case "tts.stream.start":
                    print("[TTS] Stream started")
                    
                case "tts.stream.end":
                    let elapsed = streamStartTime.map { Date().timeIntervalSince($0) } ?? 0
                    print("[TTS] Stream ended in \(String(format: "%.2f", elapsed))s, \(audioBuffer.count) bytes")
                    if audioBuffer.isEmpty {
                        // Server returned no audio, fallback
                        if let text = pendingText {
                            speakLocal(text)
                        }
                    } else {
                        playAudio()
                    }
                    
                case "tts.stream.error":
                    print("[TTS] Server error: \(json["error"] ?? "unknown"), using local TTS")
                    isStreaming = false
                    if let text = pendingText {
                        speakLocal(text)
                    }
                    
                default:
                    break
                }
            }
            
        case .data(let data):
            audioBuffer.append(data)
            
        @unknown default:
            break
        }
    }
    
    private func playAudio() {
        pendingText = nil  // Clear fallback text
        
        guard !audioBuffer.isEmpty else {
            isStreaming = false
            return
        }
        
        setupAudioSession()
        
        do {
            audioPlayer = try AVAudioPlayer(data: audioBuffer)
            audioPlayer?.prepareToPlay()
            isPlaying = true
            audioPlayer?.play()
            print("[TTS] Playing ElevenLabs audio")
            
            Task {
                while audioPlayer?.isPlaying == true {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                await MainActor.run {
                    self.isPlaying = false
                    self.isStreaming = false
                }
            }
        } catch {
            print("[TTS] Play error: \(error), falling back to local")
            isStreaming = false
            if let text = pendingText {
                speakLocal(text)
            }
        }
    }
    
    // MARK: - Local TTS Fallback
    
    private func speakLocal(_ text: String) {
        pendingText = nil
        isStreaming = false
        
        // Clean text for TTS
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }
        
        // Strip markdown
        cleanText = cleanText
            .replacingOccurrences(of: "```[^`]*```", with: " code block ", options: .regularExpression)
            .replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
        
        setupAudioSession()
        
        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        
        isPlaying = true
        print("[TTS] Playing local TTS (fallback)")
        synthesizer.speak(utterance)
        
        Task {
            while synthesizer.isSpeaking {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            await MainActor.run {
                self.isPlaying = false
            }
        }
    }
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, 
                                         options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try audioSession.setActive(true)
        } catch {
            print("[TTS] Audio session error: \(error)")
        }
    }
    
    func stopPlayback() {
        audioPlayer?.stop()
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isStreaming = false
        pendingText = nil
    }
}
