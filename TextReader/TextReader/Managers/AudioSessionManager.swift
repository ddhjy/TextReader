import AVFoundation
import MediaPlayer

/// Audio session manager for handling audio-related system interactions
/// Including session configuration, control center display, audio interruption and remote control commands
class AudioSessionManager: NSObject {
    private weak var contentViewModel: ContentViewModel?
    private var isAudioSessionActive = false
    private var isSystemPlaybackActive = false

    override init() {
        super.init()
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleAudioSessionInterruption), 
            name: AVAudioSession.interruptionNotification, 
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleAudioRouteChange), 
            name: AVAudioSession.routeChangeNotification, 
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleAppDidBecomeActive), 
            name: UIApplication.didBecomeActiveNotification, 
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleAppDidEnterBackground), 
            name: UIApplication.didEnterBackgroundNotification, 
            object: nil
        )
    }
    
    func registerViewModel(_ viewModel: ContentViewModel) {
        self.contentViewModel = viewModel
    }

    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // 设置音频会话类别为播放，模式为语音朗读
            try session.setCategory(.playback, mode: .spokenAudio, options: [])
            
            // 激活音频会话
            try session.setActive(true)
            isAudioSessionActive = true
            
            // 强制同步播放状态
            synchronizePlaybackState(force: true)
            
        } catch {
            isAudioSessionActive = false
        }
    }

    func setupRemoteCommandCenter(playAction: @escaping () -> Void,
                                  pauseAction: @escaping () -> Void,
                                  nextAction: (() -> Void)? = nil,
                                  previousAction: (() -> Void)? = nil) {
        clearRemoteCommandTargets()
        
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] event in
            self?.isSystemPlaybackActive = true
            playAction()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] event in
            self?.isSystemPlaybackActive = false
            pauseAction()
            return .success
        }

        if let next = nextAction {
            commandCenter.nextTrackCommand.isEnabled = true
            commandCenter.nextTrackCommand.addTarget { _ in 
                next()
                return .success 
            }
        } else {
            commandCenter.nextTrackCommand.isEnabled = false
        }

        if let prev = previousAction {
            commandCenter.previousTrackCommand.isEnabled = true
            commandCenter.previousTrackCommand.addTarget { _ in 
                prev()
                return .success 
            }
        } else {
            commandCenter.previousTrackCommand.isEnabled = false
        }

        print("Remote command center configured")
    }
    
    /// 清除远程命令中心的现有目标
    private func clearRemoteCommandTargets() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
    }

    /// 更新控制中心的媒体信息
    func updateNowPlayingInfo(title: String?, isPlaying: Bool, currentPage: Int? = nil, totalPages: Int? = nil) {
        // 确保在主线程执行
        DispatchQueue.main.async {
            if isPlaying {
                // 播放状态：激活音频会话并设置播放信息
                // 音频会话操作移到后台线程，避免阻塞UI
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let audioSession = AVAudioSession.sharedInstance()
                        try audioSession.setActive(true)
                        DispatchQueue.main.async {
                            self.isAudioSessionActive = true
                        }
                    } catch {
                        // 音频会话设置失败，但不影响播放信息显示
                    }
                }
                
                // 立即设置播放信息，不等待音频会话
                var nowPlayingInfo: [String: Any] = [:]
                nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? "TextReader"
                nowPlayingInfo[MPMediaItemPropertyArtist] = "TextReader App"
                nowPlayingInfo[MPMediaItemPropertyMediaType] = MPMediaType.audioBook.rawValue
                nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
                nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
                
                let duration = 3600.0
                nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
                
                if let current = currentPage, let total = totalPages, total > 0 {
                    let progress = Double(current - 1) / Double(total)
                    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = duration * progress
                } else {
                    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
                }
                
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                self.isSystemPlaybackActive = true
                
            } else {
                // 暂停状态：卡马克式最直接方法 - 立即清空播放信息，音频会话操作放后台
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                self.isSystemPlaybackActive = false
                
                // 音频会话停用操作移到后台，避免阻塞UI
                if self.isAudioSessionActive {
                    DispatchQueue.global(qos: .utility).async {
                        do {
                            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                            DispatchQueue.main.async {
                                self.isAudioSessionActive = false
                            }
                        } catch {
                            // 停用音频会话失败，不影响播放信息清空
                        }
                    }
                }
            }
        }
    }
    
    /// 同步播放状态，确保系统控制中心和应用内状态一致
    func synchronizePlaybackState(force: Bool = false) {
        guard let viewModel = contentViewModel else { return }
        
        let isAppPlaying = viewModel.isReading
        
        // 卡马克式简单方案：直接更新，不要复杂的条件判断
        if force || (isAppPlaying != isSystemPlaybackActive) {
            updateNowPlayingInfo(
                title: viewModel.currentBookTitle,
                isPlaying: isAppPlaying,
                currentPage: viewModel.currentPageIndex + 1,
                totalPages: viewModel.pages.count
            )
        }
    }
    
    // MARK: - 通知处理方法
    
    /// 处理音频会话中断（如电话呼入）
    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeRawValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRawValue) else {
            return
        }
        
        switch type {
        case .began:
            // 中断开始，暂停播放
            print("音频会话被中断：开始")
            isSystemPlaybackActive = false
            
            contentViewModel?.stopReading()
            
        case .ended:
            // 中断结束，根据选项判断是否需要恢复播放
            print("音频会话中断：结束")
            guard let optionsRawValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRawValue)
            
            // 如果带有"可以恢复"选项，并且中断前处于播放状态，则恢复音频会话和播放
            if options.contains(.shouldResume) {
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    isAudioSessionActive = true
                    // 不要自动恢复语音播放，避免意外语音干扰用户
                } catch {
                    print("恢复音频会话失败: \(error)")
                }
            }
            
        @unknown default:
            print("未知的音频会话中断类型")
        }
    }
    
    /// 处理音频路由变更（如耳机插拔）
    @objc private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonRawValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonRawValue) else {
            return
        }
        
        // 仅处理旧输出设备被断开的情况
        if reason == .oldDeviceUnavailable {
            // 获取之前的音频路由
            guard let routeDescription = userInfo[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription,
                  let output = routeDescription.outputs.first else {
                return
            }
            
            // 如果之前是耳机或外部设备，断开后自动暂停播放
            let portTypes: [AVAudioSession.Port] = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .airPlay, .carAudio]
            if portTypes.contains(output.portType) {
                print("音频输出设备断开：\(output.portType.rawValue)")
                
                if isSystemPlaybackActive {
                    contentViewModel?.stopReading()
                }
            }
        }
    }
    
    /// 处理应用前台激活事件
    @objc private func handleAppDidBecomeActive(_ notification: Notification) {
        // 当应用进入前台后，确保音频会话处于激活状态
        // 旧代码: synchronizePlaybackState(force: true)
        
        // 新代码: 强制重新激活音频会话，确保系统准备就绪
        print("应用返回前台，重新激活音频会话。")
        setupAudioSession()
    }
    
    /// 处理应用进入后台事件
    @objc private func handleAppDidEnterBackground(_ notification: Notification) {
        // 应用进入后台时的处理可以在这里添加
    }
    
    /// 取消激活音频会话
    func deactivateAudioSession() {
        guard isAudioSessionActive else { return }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isAudioSessionActive = false
        } catch {
            // 停用音频会话失败，但不影响应用功能
        }
    }
}

// 扩展提供可读的路由变化原因描述
extension AVAudioSession.RouteChangeReason {
    /// 获取路由变化原因的文字描述
    var description: String {
        switch self {
        case .unknown: return "未知原因"
        case .newDeviceAvailable: return "新设备可用"
        case .oldDeviceUnavailable: return "旧设备不可用"
        case .categoryChange: return "类别变化"
        case .override: return "覆盖"
        case .wakeFromSleep: return "从睡眠唤醒"
        case .noSuitableRouteForCategory: return "当前类别没有合适的路由"
        case .routeConfigurationChange: return "路由配置变化"
        @unknown default: return "未知原因"
        }
    }
} 
