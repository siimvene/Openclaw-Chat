import Foundation
import AVFoundation
import Speech
import UIKit

@MainActor
class VoiceInput: ObservableObject {
    @Published var isRecording = false
    @Published var transcription = ""
    @Published var isAuthorized = false
    @Published var errorMessage: String?
    @Published var isContinuousMode = false
    @Published var audioLevel: Float = 0
    @Published var isSpeaking = false
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let synthesizer = AVSpeechSynthesizer()
    private var levelTimer: Timer?
    
    // Callback for when transcription is ready to send
    var onFinalTranscription: ((String) -> Void)?
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5  // Auto-stop after 1.5s of silence
    private var isStoppingManually = false  // Track manual stops to suppress errors
    private var lastTranscriptionTime: Date?
    
    init() {
        requestAuthorization()
    }
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                switch status {
                case .authorized:
                    self?.isAuthorized = true
                case .denied:
                    self?.isAuthorized = false
                    self?.errorMessage = "Speech recognition denied"
                case .restricted:
                    self?.isAuthorized = false
                    self?.errorMessage = "Speech recognition restricted"
                case .notDetermined:
                    self?.isAuthorized = false
                @unknown default:
                    self?.isAuthorized = false
                }
            }
        }
    }
    
    func startRecording() {
        guard isAuthorized,
              let recognizer = speechRecognizer,
              recognizer.isAvailable else {
            errorMessage = "Speech recognizer not available"
            return
        }
        
        // Stop TTS if playing
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        stopRecordingInternal()
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
            return
        }
        
        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            
            // Calculate audio level for visualization
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            if let data = channelData, frameLength > 0 {
                var sum: Float = 0
                for i in 0..<frameLength {
                    sum += abs(data[i])
                }
                let avg = sum / Float(frameLength)
                Task { @MainActor in
                    self?.audioLevel = min(avg * 10, 1.0)
                }
            }
        }
        
        do {
            try engine.start()
        } catch {
            errorMessage = "Audio engine error: \(error.localizedDescription)"
            return
        }
        
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                if let result = result {
                    self?.transcription = result.bestTranscription.formattedString
                    self?.lastTranscriptionTime = Date()
                    
                    // Reset silence timer - auto-stop after silence
                    self?.resetSilenceTimer()
                    
                    if result.isFinal {
                        self?.handleFinalResult()
                    }
                }
                
                if let error = error {
                    // Suppress errors from manual stop
                    if self?.isStoppingManually == true {
                        return
                    }
                    
                    let nsError = error as NSError
                    // Suppress common non-error codes:
                    // 216 = no speech detected, 209 = cancelled, 203 = retry, 1110 = no speech
                    let suppressedCodes = [216, 209, 203, 1110, 301]
                    if nsError.domain == "kAFAssistantErrorDomain" && suppressedCodes.contains(nsError.code) {
                        return
                    }
                    // Also suppress "cancelled" errors
                    if nsError.localizedDescription.lowercased().contains("cancel") {
                        return
                    }
                    
                    self?.errorMessage = error.localizedDescription
                    self?.stopRecordingInternal()
                }
            }
        }
        
        audioEngine = engine
        recognitionRequest = request
        isRecording = true
        errorMessage = nil
        
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    @discardableResult
    func stopRecording() -> String {
        isStoppingManually = true
        let result = transcription
        stopRecordingInternal()
        
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        // Reset manual stop flag after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.isStoppingManually = false
        }
        
        return result
    }
    
    func toggleContinuousMode() {
        isContinuousMode.toggle()
        if isContinuousMode && !isRecording {
            startRecording()
        } else if !isContinuousMode && isRecording {
            let text = stopRecording()
            if !text.isEmpty {
                onFinalTranscription?(text)
            }
        }
    }
    
    // MARK: - TTS
    
    func speak(_ text: String) {
        // Skip empty or whitespace-only text
        var cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else {
            print("[Voice] Skipping empty text for TTS")
            return
        }
        
        // Skip server-side media references (OpenClaw TTS audio files)
        // Format: MEDIA:/path/to/file or similar
        if cleanText.hasPrefix("MEDIA:") {
            print("[Voice] Skipping server-side TTS media reference")
            return
        }
        
        // Strip any markdown or special formatting that TTS can't handle well
        cleanText = cleanText
            .replacingOccurrences(of: "```[^`]*```", with: " code block ", options: .regularExpression)
            .replacingOccurrences(of: "`[^`]+`", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\*\\*([^*]+)\\*\\*", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "\\*([^*]+)\\*", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "#+\\s*", with: "", options: .regularExpression)
        
        guard !cleanText.isEmpty else {
            print("[Voice] Text became empty after cleaning")
            return
        }
        
        // Stop recording while speaking
        if isRecording {
            stopRecordingInternal()
        }
        
        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Use playAndRecord to allow smooth transition from recording
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("[Voice] TTS audio session error: \(error)")
            DispatchQueue.main.async {
                self.errorMessage = "Audio error: \(error.localizedDescription)"
            }
            return
        }
        
        // Try to use enhanced/premium voices (require download in iOS Settings > Accessibility > Spoken Content)
        let utterance = AVSpeechUtterance(string: cleanText)
        
        // Priority: Premium > Enhanced > Compact voices
        let preferredVoices = [
            "com.apple.voice.premium.en-US.Zoe",      // Premium (best quality)
            "com.apple.voice.premium.en-US.Evan",
            "com.apple.voice.enhanced.en-US.Zoe",    // Enhanced (good quality)
            "com.apple.voice.enhanced.en-US.Evan",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.ttsbundle.siri_Nicky_en-US_compact",  // Siri voice
            "com.apple.ttsbundle.siri_Aaron_en-US_compact",
            "com.apple.voice.compact.en-US.Samantha" // Fallback compact
        ]
        
        var selectedVoice: AVSpeechSynthesisVoice?
        for voiceId in preferredVoices {
            if let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
                selectedVoice = voice
                print("[Voice] Using voice: \(voiceId)")
                break
            }
        }
        utterance.voice = selectedVoice ?? AVSpeechSynthesisVoice(language: "en-US")
        
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05  // Slightly faster
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.05
        
        isSpeaking = true
        print("[Voice] Starting TTS for: \(cleanText.prefix(50))...")
        
        // Check if voices are available (simulator sometimes has none)
        let availableVoices = AVSpeechSynthesisVoice.speechVoices()
        if availableVoices.isEmpty {
            print("[Voice] Warning: No TTS voices available (simulator issue)")
        }
        
        synthesizer.speak(utterance)
        
        // Monitor when speaking ends using a timer to avoid view update conflicts
        monitorSpeechCompletion()
    }
    
    private func monitorSpeechCompletion() {
        // Use Task with sleep to monitor speech completion
        Task { @MainActor in
            // Wait a moment before starting to check
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            while synthesizer.isSpeaking {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            
            // Use asyncAfter to defer state update outside of any view update cycle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self = self else { return }
                self.isSpeaking = false
                print("[Voice] TTS finished")
                
                // Resume recording in continuous mode
                if self.isContinuousMode {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.startRecording()
                    }
                }
            }
        }
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
    
    // MARK: - Private
    
    private func handleFinalResult() {
        if isContinuousMode && !transcription.isEmpty {
            let text = transcription
            onFinalTranscription?(text)
            transcription = ""
            
            // Restart recording for next utterance
            stopRecordingInternal()
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                startRecording()
            }
        }
    }
    
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isRecording, !self.transcription.isEmpty else { return }
                
                // Auto-stop and submit after silence
                let text = self.transcription
                print("[Voice] Auto-stopping after silence, transcription: \(text.prefix(50))...")
                
                self.isStoppingManually = true
                self.stopRecordingInternal()
                self.isStoppingManually = false
                
                // Submit the transcription
                self.onFinalTranscription?(text)
                self.transcription = ""
            }
        }
    }
    
    private func stopRecordingInternal() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecording = false
        audioLevel = 0
    }
}
