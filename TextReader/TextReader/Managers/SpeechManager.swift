import AVFoundation
import UIKit // For UIBackgroundTaskIdentifier

class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking: Bool = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    // Callbacks for ViewModel
    var onSpeechFinish: (() -> Void)?
    var onSpeechStart: (() -> Void)?
    var onSpeechPause: (() -> Void)?
    var onSpeechResume: (() -> Void)?


    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func getAvailableVoices(languagePrefix: String = "zh") -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: languagePrefix) }
    }

    func startReading(text: String, voice: AVSpeechSynthesisVoice?, rate: Float) {
        guard !text.isEmpty else { return }

        stopReading() // Ensure any previous speech is stopped

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "zh-CN") // Default fallback
        // Adjust rate relative to default rate
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate

        // Start background task for background audio playback
        startBackgroundTask()

        synthesizer.speak(utterance)
        isSpeaking = true
        onSpeechStart?()
    }

    func stopReading() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate) // Use immediate for quicker stop
        }
        // The delegate method speechSynthesizer(_:didCancel:) will handle isSpeaking = false and ending background task
    }

    func pauseReading() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            isSpeaking = false // Consider paused as not actively speaking for UI state
            onSpeechPause?()
            // Keep background task active during pause
        }
    }

    func resumeReading() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isSpeaking = true
            onSpeechResume?()
        }
    }


    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        endBackgroundTask()
        onSpeechFinish?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        endBackgroundTask()
        // Optionally add an onSpeechCancel callback if needed
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        // Delegate method confirms pause state if needed
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        // Delegate method confirms continue state if needed
    }

    // MARK: - Background Task Management

    private func startBackgroundTask() {
        endBackgroundTask() // End any previous task first
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
} 