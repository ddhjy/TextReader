import AVFoundation
import UIKit // For UIBackgroundTaskIdentifier

class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking: Bool = false
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
    // 记录最后一次发生错误的时间
    private var lastErrorTime: Date?
    // 记录是否发生错误
    private var didEncounterError = false
    // 最后一次尝试播放的文本
    private var lastText: String?
    private var lastVoice: AVSpeechSynthesisVoice?
    private var lastRate: Float = 1.0

    // Callbacks for ViewModel
    var onSpeechFinish: (() -> Void)?
    var onSpeechStart: (() -> Void)?
    var onSpeechPause: (() -> Void)?
    var onSpeechResume: (() -> Void)?
    var onSpeechError: (() -> Void)? // 添加错误回调


    override init() {
        super.init()
        synthesizer.delegate = self
        
        // 初始化时重置状态
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
        print("SpeechManager: 开始朗读请求")
        
        guard !text.isEmpty else {
            print("SpeechManager: 无法朗读空文本")
            didEncounterError = true
            onSpeechError?()
            return 
        }
        
        // 保存当前参数
        lastText = text
        lastVoice = voice
        lastRate = rate

        // 重置错误状态
        didEncounterError = false
        
        // 确保先停止任何正在进行的播放
        stopReading()
        
        // 开始新的背景任务
        startBackgroundTask()

        // 延迟一小段时间再开始，确保之前的操作完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice ?? AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * rate
            
            print("SpeechManager: 开始语音合成")
            self.synthesizer.speak(utterance)
            
            // 检查是否成功开始播放
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
        
        // 结束任何现有播放
        if synthesizer.isSpeaking || synthesizer.isPaused {
            print("SpeechManager: 停止当前语音")
            synthesizer.stopSpeaking(at: .immediate) // Use immediate for quicker stop
        }
        
        // 确保状态已重置
        if isSpeaking {
            isSpeaking = false
            endBackgroundTask()
        }
    }

    func pauseReading() {
        if synthesizer.isSpeaking {
            print("SpeechManager: 暂停朗读")
            synthesizer.pauseSpeaking(at: .word)
            isSpeaking = false // Consider paused as not actively speaking for UI state
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
    
    // 尝试重新播放上次内容
    func retryLastReading() {
        if let text = lastText, let voice = lastVoice {
            print("SpeechManager: 重试上次朗读")
            startReading(text: text, voice: voice, rate: lastRate)
        }
    }


    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // 在主线程更新状态
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("SpeechManager: 朗读完成")
            self.isSpeaking = false
            self.endBackgroundTask()
            self.onSpeechFinish?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // 在主线程更新状态
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("SpeechManager: 朗读被取消")
            self.isSpeaking = false
            self.endBackgroundTask()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        // 在主线程更新状态
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("SpeechManager: 朗读已暂停")
            self.isSpeaking = false
            self.onSpeechPause?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        // 在主线程更新状态
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            print("SpeechManager: 朗读已恢复")
            self.isSpeaking = true
            self.onSpeechResume?()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // 在主线程更新状态
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
        // 监控朗读进度，确保正在进行
    }

    // MARK: - Background Task Management

    private func startBackgroundTask() {
        endBackgroundTask() // End any previous task first
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            // 任务即将超时的处理
            print("SpeechManager: 后台任务即将超时")
            self?.endBackgroundTask()
            
            // 如果此时正在播放，可能需要报告错误
            if self?.isSpeaking == true {
                self?.didEncounterError = true
                self?.onSpeechError?()
            }
        }
        
        print("SpeechManager: 开始后台任务 ID=\(backgroundTask.rawValue)")
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            print("SpeechManager: 结束后台任务 ID=\(backgroundTask.rawValue)")
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
} 