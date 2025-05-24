import AVFoundation
import UIKit

/// 语音管理器，负责文本的语音合成和朗读控制
/// 封装AVSpeechSynthesizer功能，提供朗读控制并管理后台任务
class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject, @unchecked Sendable {
    /// 语音合成器
    private let synthesizer = AVSpeechSynthesizer()
    /// 当前是否正在朗读
    @Published private(set) var isSpeaking: Bool = false
    /// 后台任务标识符
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    /// 记录最后一次出错的时间
    private var lastErrorTime: Date?
    /// 指示在播放过程中是否遇到了错误
    private var didEncounterError = false
    /// 存储最后尝试朗读的文本，用于重试功能
    private var lastText: String?
    /// 存储最后使用的语音
    private var lastVoice: AVSpeechSynthesisVoice?
    /// 存储最后使用的朗读速率
    private var lastRate: Float = 1.0

    /// 回调函数
    var onSpeechFinish: (() -> Void)?
    var onSpeechStart: (() -> Void)?
    var onSpeechPause: (() -> Void)?
    var onSpeechResume: (() -> Void)?
    var onSpeechError: (() -> Void)?

    /// 初始化语音管理器
    override init() {
        super.init()
        synthesizer.delegate = self
        resetState()
    }
    
    /// 重置内部状态
    private func resetState() {
        isSpeaking = false
        didEncounterError = false
        lastText = nil
        lastVoice = nil
    }

    /// 获取指定语言前缀的可用语音列表
    /// - Parameter languagePrefix: 语言前缀，默认为"zh"（中文）
    /// - Returns: 符合指定语言的语音列表
    func getAvailableVoices(languagePrefix: String = "zh") -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: languagePrefix) }
    }

    /// 开始朗读文本
    /// - Parameters:
    ///   - text: 要朗读的文本
    ///   - voice: 使用的语音，如果为nil则使用默认中文语音
    ///   - rate: 朗读速率
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
        
        // 开始后台任务，允许语音合成在应用进入后台时继续
        startBackgroundTask()

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate
        
        print("语音管理器: 开始语音合成")
        self.synthesizer.speak(utterance)
        
        // 延迟检查是否成功开始播放
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            if !self.synthesizer.isSpeaking && !self.didEncounterError {
                print("语音管理器: 检测到播放未能成功开始")
                self.didEncounterError = true
                self.onSpeechError?()
            }
        }
    }

    /// 停止朗读
    func stopReading() {
        print("语音管理器: 收到停止朗读请求")
        
        if synthesizer.isSpeaking || synthesizer.isPaused {
            print("语音管理器: 停止当前朗读")
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        if isSpeaking {
            isSpeaking = false
            endBackgroundTask()
        }
    }

    /// 暂停朗读
    func pauseReading() {
        if synthesizer.isSpeaking {
            print("语音管理器: 暂停朗读")
            synthesizer.pauseSpeaking(at: .word)
            isSpeaking = false
            onSpeechPause?()
            // 在暂停期间保持后台任务活跃
        }
    }

    /// 恢复朗读
    func resumeReading() {
        if synthesizer.isPaused {
            print("语音管理器: 恢复朗读")
            synthesizer.continueSpeaking()
            isSpeaking = true
            onSpeechResume?()
        }
    }
    
    /// 尝试重新朗读上次的文本
    func retryLastReading() {
        if let text = lastText, let voice = lastVoice {
            print("语音管理器: 重试上次朗读")
            startReading(text: text, voice: voice, rate: lastRate)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate 代理方法

    /// 朗读完成时的回调
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读完成")
            self.isSpeaking = false
            self.endBackgroundTask()
            self.onSpeechFinish?()
        }
    }

    /// 朗读被取消时的回调
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读被取消")
            self.isSpeaking = false
            self.endBackgroundTask()
        }
    }

    /// 朗读被暂停时的回调
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读被暂停")
            self.isSpeaking = false
            self.onSpeechPause?()
        }
    }

    /// 朗读继续时的回调
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读已恢复")
            self.isSpeaking = true
            self.onSpeechResume?()
        }
    }
    
    /// 朗读开始时的回调
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("语音管理器: 朗读已开始")
            self.isSpeaking = true
            self.onSpeechStart?()
        }
    }
    
    /// 朗读到文本中的某个范围时的回调
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, 
                           willSpeakRangeOfSpeechString characterRange: NSRange, 
                           utterance: AVSpeechUtterance) {
    }

    // MARK: - 后台任务管理

    /// 开始后台任务，允许应用在后台继续语音合成
    private func startBackgroundTask() {
        endBackgroundTask() // 先结束之前的任务
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // 处理任务超时
            print("语音管理器: 后台任务即将超时")
            self?.endBackgroundTask()
            
            // 如果任务超时时仍在朗读，则报告错误
            if self?.isSpeaking == true {
                self?.didEncounterError = true
                self?.onSpeechError?()
            }
        }
        
        print("语音管理器: 已开始后台任务 ID=\(backgroundTask.rawValue)")
    }

    /// 结束当前后台任务（如果存在）
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            print("语音管理器: 已结束后台任务 ID=\(backgroundTask.rawValue)")
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
} 