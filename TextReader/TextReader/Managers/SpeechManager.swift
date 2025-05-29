import AVFoundation
import UIKit

/// 语音管理器，负责文本的语音合成和朗读控制
/// 封装AVSpeechSynthesizer功能，提供朗读控制并管理后台任务
class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking: Bool = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    private var lastErrorTime: Date?
    private var didEncounterError = false
    private var lastText: String?
    private var lastVoice: AVSpeechSynthesisVoice?
    private var lastRate: Float = 1.0

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

    func getAvailableVoices(languagePrefix: String = "zh") -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: languagePrefix) }
    }

    func startReading(text: String, voice: AVSpeechSynthesisVoice?, rate: Float) {
        print("语音管理器: 收到开始朗读请求")
        
        guard !text.isEmpty else {
            print("语音管理器: 无法朗读空文本")
            didEncounterError = true
            DispatchQueue.main.async {
                self.onSpeechError?()
            }
            return 
        }
        
        lastText = text
        lastVoice = voice
        lastRate = rate
        didEncounterError = false
        
        startBackgroundTask()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate
        
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
    }

    func stopReading() {
        print("🔇 SpeechManager: 收到停止朗读请求")
        print("🔇 当前状态 - isSpeaking: \(isSpeaking), synthesizer.isSpeaking: \(synthesizer.isSpeaking), synthesizer.isPaused: \(synthesizer.isPaused)")
        
        // 卡马克式简单方案：直接停止，不要复杂的延迟调用
        if synthesizer.isSpeaking || synthesizer.isPaused {
            print("🔇 正在停止语音合成器")
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        if isSpeaking {
            print("🔇 更新内部状态")
            isSpeaking = false
            endBackgroundTask()
            print("🔇 触发暂停回调")
            onSpeechPause?()
        }
        
        print("🔇 停止朗读完成 - 最终状态: isSpeaking: \(isSpeaking)")
    }

    func pauseReading() {
        if synthesizer.isSpeaking {
            print("语音管理器: 暂停朗读")
            synthesizer.pauseSpeaking(at: .word)
            isSpeaking = false
            onSpeechPause?()
        }
    }

    func resumeReading() {
        if synthesizer.isPaused {
            print("语音管理器: 恢复朗读")
            synthesizer.continueSpeaking()
            isSpeaking = true
            onSpeechResume?()
        }
    }
    
    func retryLastReading() {
        if let text = lastText, let voice = lastVoice {
            print("语音管理器: 重试上次朗读")
            startReading(text: text, voice: voice, rate: lastRate)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate 代理方法

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读完成")
            self.isSpeaking = false
            self.endBackgroundTask()
            self.onSpeechFinish?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读被取消")
            self.isSpeaking = false
            self.endBackgroundTask()
            self.onSpeechPause?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读被暂停")
            self.isSpeaking = false
            self.onSpeechPause?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读已恢复")
            self.isSpeaking = true
            self.onSpeechResume?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读已开始")
            self.isSpeaking = true
            self.onSpeechStart?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, 
                           willSpeakRangeOfSpeechString characterRange: NSRange, 
                           utterance: AVSpeechUtterance) {
    }

    // MARK: - 后台任务管理

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