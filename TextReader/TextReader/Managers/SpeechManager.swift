import AVFoundation
import UIKit // For UIBackgroundTaskIdentifier

class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking: Bool = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    /// Tracks the last time an error occurred for error handling logic
    private var lastErrorTime: Date?
    /// Indicates whether an error has been encountered during playback
    private var didEncounterError = false
    /// Stores the last text that was attempted to be read for retry functionality
    private var lastText: String?
    private var lastVoice: AVSpeechSynthesisVoice?
    private var lastRate: Float = 1.0

    /// Callbacks for ViewModel to respond to speech events
    var onSpeechFinish: (() -> Void)?
    var onSpeechStart: (() -> Void)?
    var onSpeechPause: (() -> Void)?
    var onSpeechResume: (() -> Void)?
    var onSpeechError: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
        resetState()
    }
    
    private func resetState() {
        isSpeaking = false
        didEncounterError = false
        lastText = nil
        lastVoice = nil
    }

    /// Returns available voices for the specified language prefix
    func getAvailableVoices(languagePrefix: String = "zh") -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: languagePrefix) }
    }

    func startReading(text: String, voice: AVSpeechSynthesisVoice?, rate: Float) {
        print("SpeechManager: 开始朗读请求")
        
        guard !text.isEmpty else {
            print("SpeechManager: 无法朗读空文本")
            didEncounterError = true
            onSpeechError?()
            return 
        }
        
        lastText = text
        lastVoice = voice
        lastRate = rate

        didEncounterError = false
        
        // Ensure any ongoing playback is stopped
        stopReading()
        
        // Start background task to allow speech synthesis to continue in background
        startBackgroundTask()

        // Add a short delay to ensure previous operations are completed
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate
            
            print("SpeechManager: 开始语音合成")
            self.synthesizer.speak(utterance)
            
            // Check if playback actually started successfully
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                if !self.synthesizer.isSpeaking && !self.didEncounterError {
                    print("SpeechManager: 检测到播放没有成功开始")
                    self.didEncounterError = true
                    self.onSpeechError?()
                }
            }
        }
    }

    func stopReading() {
        print("SpeechManager: 停止朗读请求")
        
        if synthesizer.isSpeaking || synthesizer.isPaused {
            print("SpeechManager: 停止当前语音")
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        if isSpeaking {
            isSpeaking = false
            endBackgroundTask()
        }
    }

    func pauseReading() {
        if synthesizer.isSpeaking {
            print("SpeechManager: 暂停朗读")
            synthesizer.pauseSpeaking(at: .word)
            isSpeaking = false
            onSpeechPause?()
            // Keep background task active during pause
        }
    }

    func resumeReading() {
        if synthesizer.isPaused {
            print("SpeechManager: 恢复朗读")
            synthesizer.continueSpeaking()
            isSpeaking = true
            onSpeechResume?()
        }
    }
    
    /// Attempts to retry reading the last text that was played
    func retryLastReading() {
        if let text = lastText, let voice = lastVoice {
            print("SpeechManager: 重试上次朗读")
            startReading(text: text, voice: voice, rate: lastRate)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("SpeechManager: 朗读完成")
            self.isSpeaking = false
            self.endBackgroundTask()
            self.onSpeechFinish?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("SpeechManager: 朗读被取消")
            self.isSpeaking = false
            self.endBackgroundTask()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("SpeechManager: 朗读已暂停")
            self.isSpeaking = false
            self.onSpeechPause?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("SpeechManager: 朗读已恢复")
            self.isSpeaking = true
            self.onSpeechResume?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("SpeechManager: 朗读已开始")
            self.isSpeaking = true
            self.onSpeechStart?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, 
                           willSpeakRangeOfSpeechString characterRange: NSRange, 
                           utterance: AVSpeechUtterance) {
        // Monitor reading progress to ensure it's ongoing
    }

    // MARK: - Background Task Management

    /// Starts a background task to allow speech synthesis to continue when app is in background
    private func startBackgroundTask() {
        endBackgroundTask() // End any previous task first
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // Handle task timeout
            print("SpeechManager: 后台任务即将超时")
            self?.endBackgroundTask()
            
            // Report error if still speaking when task times out
            if self?.isSpeaking == true {
                self?.didEncounterError = true
                self?.onSpeechError?()
            }
        }
        
        print("SpeechManager: 开始后台任务 ID=\(backgroundTask.rawValue)")
    }

    /// Ends the current background task if one exists
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            print("SpeechManager: 结束后台任务 ID=\(backgroundTask.rawValue)")
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
} 