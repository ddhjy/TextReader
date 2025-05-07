import AVFoundation
import MediaPlayer

/// 音频会话管理器，负责处理音频相关的系统交互
/// 包括会话配置、控制中心显示、音频中断和远程控制命令
class AudioSessionManager: NSObject {
    /// 内容视图模型的弱引用，用于状态同步和回调
    private weak var contentViewModel: ContentViewModel?
    /// 音频会话当前是否处于激活状态
    private var isAudioSessionActive = false
    
    /// 跟踪系统播放状态，确保与系统事件保持一致
    private var isSystemPlaybackActive = false

    /// 初始化音频会话管理器
    override init() {
        super.init()
        setupNotifications()
    }
    
    /// 析构函数，移除通知观察者
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// 设置音频会话相关通知的观察者
    private func setupNotifications() {
        // 音频会话中断通知
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleAudioSessionInterruption), 
            name: AVAudioSession.interruptionNotification, 
            object: nil
        )
        
        // 音频路由变化通知
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleAudioRouteChange), 
            name: AVAudioSession.routeChangeNotification, 
            object: nil
        )
        
        // 应用进入前台通知
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleAppDidBecomeActive), 
            name: UIApplication.didBecomeActiveNotification, 
            object: nil
        )
        
        // 应用进入后台通知
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleAppDidEnterBackground), 
            name: UIApplication.didEnterBackgroundNotification, 
            object: nil
        )
    }
    
    /// 注册内容视图模型，用于音频事件回调
    func registerViewModel(_ viewModel: ContentViewModel) {
        self.contentViewModel = viewModel
    }

    /// 设置音频会话，配置为播放模式
    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
            isAudioSessionActive = true
            print("音频会话已配置为播放模式")
            
            // 确保初始化时控制中心状态正确
            synchronizePlaybackState(force: true)
        } catch {
            print("设置音频会话失败: \(error)")
            isAudioSessionActive = false
        }
    }

    /// 设置远程控制中心，处理锁屏和控制中心的媒体控制
    func setupRemoteCommandCenter(playAction: @escaping () -> Void,
                                  pauseAction: @escaping () -> Void,
                                  nextAction: (() -> Void)? = nil,
                                  previousAction: (() -> Void)? = nil) {
        // 清除已有的目标，避免重复添加
        clearRemoteCommandTargets()
        
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] event in
            print("远程命令: 播放")
            self?.isSystemPlaybackActive = true
            playAction()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] event in
            print("远程命令: 暂停")
            self?.isSystemPlaybackActive = false
            pauseAction()
            return .success
        }

        if let next = nextAction {
            commandCenter.nextTrackCommand.isEnabled = true
            commandCenter.nextTrackCommand.addTarget { _ in 
                print("远程命令: 下一曲")
                next()
                return .success 
            }
        } else {
            commandCenter.nextTrackCommand.isEnabled = false
        }

        if let prev = previousAction {
            commandCenter.previousTrackCommand.isEnabled = true
            commandCenter.previousTrackCommand.addTarget { _ in 
                print("远程命令: 上一曲")
                prev()
                return .success 
            }
        } else {
            commandCenter.previousTrackCommand.isEnabled = false
        }

        print("远程命令中心已配置")
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
        // 如果状态是停止，先尝试清除现有信息，确保控制中心刷新状态
        if !isPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        
        // 稍作延迟设置新信息，确保清除操作完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            var nowPlayingInfo: [String: Any] = [:]
            nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? "TextReader"
            nowPlayingInfo[MPMediaItemPropertyArtist] = "TextReader App"
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
            
            nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
            
            // 添加一个较小的虚拟播放时长和进度，以帮助控制中心更好地识别状态
            let fakeDuration = 3600.0 // 1小时
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = fakeDuration
            
            if let current = currentPage, let total = totalPages, total > 0 {
                nowPlayingInfo[MPNowPlayingInfoPropertyChapterNumber] = current
                nowPlayingInfo[MPNowPlayingInfoPropertyChapterCount] = total
                
                // 根据页码设置播放进度
                let progress = Double(current) / Double(total)
                nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = fakeDuration * progress
            }
            
            // 更新内部记录的系统播放状态
            self.isSystemPlaybackActive = isPlaying
            
            print("更新NowPlayingInfo: \(isPlaying ? "播放中" : "已暂停") - 强制更新")
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            
            // 如果播放已停止，额外尝试让系统识别停止状态
            if !isPlaying {
                self.forceSystemToRecognizePausedState()
            }
            
            // 确保音频会话状态与播放状态一致
            self.synchronizeAudioSessionState(with: isPlaying)
        }
    }
    
    /// 强制系统识别暂停状态
    /// 有时iOS系统可能不会正确显示暂停状态，特别是在使用语音合成时
    private func forceSystemToRecognizePausedState() {
        // 先更新为空，然后再重新设置，可以帮助系统更好地识别暂停状态
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let info = MPNowPlayingInfoCenter.default().nowPlayingInfo
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }
    }
    
    /// 同步音频会话状态与播放状态
    private func synchronizeAudioSessionState(with isPlaying: Bool) {
        if isPlaying && !isAudioSessionActive {
            self.setupAudioSession()
        }
    }
    
    /// 同步播放状态，确保系统控制中心和应用内状态一致
    func synchronizePlaybackState(force: Bool = false) {
        guard let viewModel = contentViewModel else { return }
        
        // 应用内部的播放状态
        let isAppPlaying = viewModel.isReading
        
        // 检查是否需要强制更新
        let shouldUpdate = force || (isAppPlaying != isSystemPlaybackActive)
        
        if shouldUpdate {
            // 更新系统状态
            updateNowPlayingInfo(
                title: viewModel.currentBookTitle,
                isPlaying: isAppPlaying,
                currentPage: viewModel.currentPageIndex + 1,
                totalPages: viewModel.pages.count
            )
            print("同步播放状态: 应用内\(isAppPlaying ? "正在播放" : "已暂停"), 系统\(isSystemPlaybackActive ? "正在播放" : "已暂停")")
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
            
            // 通知视图模型暂停播放
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
                
                // 如果正在播放，则暂停
                if isSystemPlaybackActive {
                    contentViewModel?.stopReading()
                }
            }
        }
    }
    
    /// 处理应用前台激活事件
    @objc private func handleAppDidBecomeActive(_ notification: Notification) {
        print("应用进入前台，同步播放状态")
        // 当应用进入前台后，确保系统媒体控制中心显示正确的状态
        synchronizePlaybackState(force: true)
    }
    
    /// 处理应用进入后台事件
    @objc private func handleAppDidEnterBackground(_ notification: Notification) {
        print("应用进入后台")
        // 应用进入后台时的处理可以在这里添加
    }
    
    /// 取消激活音频会话
    func deactivateAudioSession() {
        guard isAudioSessionActive else { return }
        
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isAudioSessionActive = false
            print("音频会话已停用")
        } catch {
            print("停用音频会话失败: \(error)")
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