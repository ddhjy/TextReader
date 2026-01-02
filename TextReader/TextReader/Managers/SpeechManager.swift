import AVFoundation
import UIKit

class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking: Bool = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    private var lastErrorTime: Date?
    private var didEncounterError = false
    private var lastText: String?
    private var lastVoice: AVSpeechSynthesisVoice?
    private var lastRate: Float = 1.0
    private var utteranceIdMap: [ObjectIdentifier: UUID] = [:]
    private var currentUtteranceId: UUID?

    var onSpeechFinish: ((UUID) -> Void)?
    var onSpeechStart: ((UUID) -> Void)?
    var onSpeechPause: ((UUID) -> Void)?
    var onSpeechResume: ((UUID) -> Void)?
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

    func getAvailableVoices(languagePrefix: String = "zh") -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: languagePrefix) }
    }

    @discardableResult
    func startReading(text: String, voice: AVSpeechSynthesisVoice?, rate: Float) -> UUID? {
        print("语音管理器: 收到开始朗读请求")
        
        guard !text.isEmpty else {
            print("语音管理器: 无法朗读空文本")
            didEncounterError = true
            DispatchQueue.main.async {
                self.onSpeechError?()
            }
            return nil
        }
        
        lastText = text
        lastVoice = voice
        lastRate = rate
        didEncounterError = false
        
        startBackgroundTask()

        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate
        
        let utteranceId = UUID()
        utteranceIdMap[ObjectIdentifier(utterance)] = utteranceId
        currentUtteranceId = utteranceId
        
        print("语音管理器: 开始语音合成")
        self.synthesizer.speak(utterance)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            if !self.synthesizer.isSpeaking && !self.didEncounterError {
                print("语音管理器: 检测到播放未能成功开始")
                self.didEncounterError = true
                self.onSpeechError?()
            }
        }
        
        return utteranceId
    }

    func stopReading() {
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        if isSpeaking {
            isSpeaking = false
            endBackgroundTask()
        }
    }

    func pauseReading() {
        if synthesizer.isSpeaking {
            print("语音管理器: 暂停朗读")
            synthesizer.pauseSpeaking(at: .word)
            isSpeaking = false
            if let id = currentUtteranceId {
                onSpeechPause?(id)
            }
        }
    }

    func resumeReading() {
        if synthesizer.isPaused {
            print("语音管理器: 恢复朗读")
            synthesizer.continueSpeaking()
            isSpeaking = true
            if let id = currentUtteranceId {
                onSpeechResume?(id)
            }
        }
    }
    
    func retryLastReading() {
        if let text = lastText, let voice = lastVoice {
            print("语音管理器: 重试上次朗读")
            _ = startReading(text: text, voice: voice, rate: lastRate)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读完成")
            self.isSpeaking = false
            self.endBackgroundTask()
            let key = ObjectIdentifier(utterance)
            let id = self.utteranceIdMap[key] ?? self.currentUtteranceId ?? UUID()
            self.utteranceIdMap.removeValue(forKey: key)
            if id == self.currentUtteranceId { self.currentUtteranceId = nil }
            self.onSpeechFinish?(id)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSpeaking = false
            self.endBackgroundTask()
            let key = ObjectIdentifier(utterance)
            let id = self.utteranceIdMap[key] ?? self.currentUtteranceId ?? UUID()
            self.utteranceIdMap.removeValue(forKey: key)
            if id == self.currentUtteranceId { self.currentUtteranceId = nil }
            self.onSpeechPause?(id)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读被暂停")
            self.isSpeaking = false
            let key = ObjectIdentifier(utterance)
            let id = self.utteranceIdMap[key] ?? self.currentUtteranceId ?? UUID()
            self.onSpeechPause?(id)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读已恢复")
            self.isSpeaking = true
            let key = ObjectIdentifier(utterance)
            let id = self.utteranceIdMap[key] ?? self.currentUtteranceId ?? UUID()
            self.onSpeechResume?(id)
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读已开始")
            self.isSpeaking = true
            let key = ObjectIdentifier(utterance)
            let id = self.utteranceIdMap[key] ?? self.currentUtteranceId ?? UUID()
            self.onSpeechStart?(id)
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, 
                           willSpeakRangeOfSpeechString characterRange: NSRange, 
                           utterance: AVSpeechUtterance) {
    }

    private func startBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            print("语音管理器: 后台任务即将超时")
            self?.endBackgroundTask()
            
            if self?.isSpeaking == true {
                self?.didEncounterError = true
                self?.onSpeechError?()
            }
        }
        
        print("语音管理器: 已开始后台任务 ID=\(backgroundTask.rawValue)")
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            print("语音管理器: 已结束后台任务 ID=\(backgroundTask.rawValue)")
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
} 