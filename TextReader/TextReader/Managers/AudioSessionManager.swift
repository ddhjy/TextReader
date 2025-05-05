import AVFoundation
import MediaPlayer

class AudioSessionManager: NSObject {
    private weak var contentViewModel: ContentViewModel?
    private var isAudioSessionActive = false
    
    /// Tracks the playback state according to system events (remote commands, interruptions) to ensure consistency.
    private var isSystemPlaybackActive = false

    override init() {
        super.init()
        setupNotifications()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Sets up observers for audio session notifications like interruptions and route changes.
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
        
        // 应用状态通知，处理从后台回到前台的同步
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
    
    /// Registers the ContentViewModel to allow callbacks on audio events.
    func registerViewModel(_ viewModel: ContentViewModel) {
        self.contentViewModel = viewModel
    }

    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
            isAudioSessionActive = true
            print("Audio session configured for playback.")
            
            // 初始化时确保控制中心状态是正确的
            synchronizePlaybackState(force: true)
        } catch {
            print("Failed to set up audio session: \(error)")
            isAudioSessionActive = false
        }
    }

    func setupRemoteCommandCenter(playAction: @escaping () -> Void,
                                  pauseAction: @escaping () -> Void,
                                  nextAction: (() -> Void)? = nil,
                                  previousAction: (() -> Void)? = nil) {
        // 清理任何现有的目标，避免重复添加
        clearRemoteCommandTargets()
        
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] event in
            print("Remote command: PLAY")
            self?.isSystemPlaybackActive = true
            playAction()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] event in
            print("Remote command: PAUSE")
            self?.isSystemPlaybackActive = false
            pauseAction()
            return .success
        }

        if let next = nextAction {
            commandCenter.nextTrackCommand.isEnabled = true
            commandCenter.nextTrackCommand.addTarget { _ in 
                print("Remote command: NEXT")
                next()
                return .success 
            }
        } else {
            commandCenter.nextTrackCommand.isEnabled = false
        }

        if let prev = previousAction {
            commandCenter.previousTrackCommand.isEnabled = true
            commandCenter.previousTrackCommand.addTarget { _ in 
                print("Remote command: PREVIOUS")
                prev()
                return .success 
            }
        } else {
            commandCenter.previousTrackCommand.isEnabled = false
        }

        print("Remote command center configured.")
    }
    
    /// Removes existing targets from remote command center commands.
    private func clearRemoteCommandTargets() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
    }

    /// Updates the MPNowPlayingInfoCenter with current book title, page, and playback state.
    func updateNowPlayingInfo(title: String?, isPlaying: Bool, currentPage: Int? = nil, totalPages: Int? = nil) {
        // 如果状态是停止播放，先尝试清除现有信息，以确保控制中心刷新状态
        if !isPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        
        // 短暂延迟后设置新的信息，确保清除操作完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            var nowPlayingInfo: [String: Any] = [:]
            nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? "TextReader"
            nowPlayingInfo[MPMediaItemPropertyArtist] = "TextReader App"
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
            
            nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
            
            // 添加一个小的虚拟播放时长和进度，帮助控制中心更好地识别状态
            let fakeDuration = 3600.0 // 1小时
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = fakeDuration
            
            if let current = currentPage, let total = totalPages, total > 0 {
                nowPlayingInfo[MPNowPlayingInfoPropertyChapterNumber] = current
                nowPlayingInfo[MPNowPlayingInfoPropertyChapterCount] = total
                
                // 根据页码设置播放进度
                let progress = Double(current) / Double(total)
                nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = fakeDuration * progress
            }
            
            // 更新我们内部记录的系统播放状态
            self.isSystemPlaybackActive = isPlaying
            
            print("Updating NowPlayingInfo: \(isPlaying ? "PLAYING" : "PAUSED") - 强制更新")
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            
            // 如果是停止播放，额外尝试让系统认识到停止状态
            if !isPlaying {
                self.forceSystemToRecognizePausedState()
            }
            
            // 确保音频会话状态与播放状态一致
            self.updateAudioSessionIfNeeded(isPlaying: isPlaying)
        }
    }
    
    /// Attempts to force the system (Control Center, Lock Screen) to recognize the paused state.
    private func forceSystemToRecognizePausedState() {
        do {
            // 暂时停用然后重新激活音频会话，帮助系统识别状态变化
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            isAudioSessionActive = true
            
            // 清除并重新设置远程控制中心
            let commandCenter = MPRemoteCommandCenter.shared()
            commandCenter.playCommand.isEnabled = true
            commandCenter.pauseCommand.isEnabled = false // 临时禁用暂停命令
            
            // 短暂延迟后恢复正常状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                commandCenter.pauseCommand.isEnabled = true
                commandCenter.playCommand.isEnabled = true
            }
        } catch {
            print("强制系统识别暂停状态时出错: \(error)")
        }
    }

    /// Ensures the audio session is active only when playback is expected.
    private func updateAudioSessionIfNeeded(isPlaying: Bool) {
        if isPlaying && !isAudioSessionActive {
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: [])
                isAudioSessionActive = true
                print("Reactivated audio session for playback")
            } catch {
                print("Failed to activate audio session: \(error)")
            }
        }
    }

    /// Clears the MPNowPlayingInfoCenter.
    func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        isSystemPlaybackActive = false
        
        // 短暂延迟后再次确认清除
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }
    
    /// Synchronizes the app's internal playback state with the Now Playing info, especially when discrepancies are detected or forced.
    func synchronizePlaybackState(force: Bool = false) {
        guard let viewModel = contentViewModel else { return }
        
        let isUIPlaying = viewModel.isReading
        
        // 只有当状态不一致或者强制同步时才进行同步
        if force || isUIPlaying != isSystemPlaybackActive {
            print("同步播放状态 - UI: \(isUIPlaying), 系统: \(isSystemPlaybackActive)")
            
            // 使用UI状态作为真实状态
            updateNowPlayingInfo(
                title: viewModel.currentBookTitle,
                isPlaying: isUIPlaying,
                currentPage: viewModel.currentPageIndex + 1,
                totalPages: viewModel.pages.count
            )
        }
    }
    
    /// Handles audio session interruptions (e.g., phone calls).
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        print("音频中断: \(type == .began ? "开始" : "结束")")
        
        switch type {
        case .began:
            // 中断开始，例如来电或其他应用开始播放音频
            isAudioSessionActive = false
            
            // 如果正在播放，立即暂停播放并更新状态
            if let viewModel = contentViewModel, viewModel.isReading {
                DispatchQueue.main.async {
                    // 确保先更新系统状态再调用暂停方法
                    self.isSystemPlaybackActive = false
                    viewModel.stopReading()
                }
            }
            
        case .ended:
            // 中断结束
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                
                // 尝试重新激活音频会话
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    isAudioSessionActive = true
                    
                    // 如果系统表明应该恢复播放，且UI显示应该在播放状态，则恢复播放
                    if options.contains(.shouldResume) && contentViewModel?.isReading == true {
                        // 应该只在用户明确表示需要恢复时恢复
                        print("系统表明可以恢复播放，但此应用让用户决定是否恢复")
                    }
                    
                    // 无论如何，确保系统状态与应用状态一致
                    DispatchQueue.main.async {
                        self.synchronizePlaybackState()
                    }
                } catch {
                    print("Failed to reactivate audio session: \(error)")
                }
            }
            
        @unknown default:
            print("Unknown audio session interruption type")
        }
    }
    
    /// Handles audio route changes (e.g., headphones unplugged).
    @objc private func handleAudioRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        print("音频路由变化: \(reason.description)")
        
        switch reason {
        case .oldDeviceUnavailable:
            // 例如拔出耳机时暂停播放
            if let viewModel = contentViewModel, viewModel.isReading {
                DispatchQueue.main.async {
                    self.isSystemPlaybackActive = false
                    viewModel.stopReading()
                }
            }
        case .newDeviceAvailable, .categoryChange:
            // 新设备连接或分类变化时，确保状态一致
            DispatchQueue.main.async {
                self.synchronizePlaybackState()
            }
        default:
            // 其他情况，也确保状态一致
            DispatchQueue.main.async {
                self.synchronizePlaybackState()
            }
        }
    }
    
    /// Synchronizes playback state when the app becomes active.
    @objc private func handleAppDidBecomeActive(notification: Notification) {
        print("应用回到前台，同步播放状态")
        DispatchQueue.main.async {
            self.synchronizePlaybackState(force: true)
        }
    }
    
    /// Ensures the Now Playing info is correctly updated when the app enters the background.
    @objc private func handleAppDidEnterBackground(notification: Notification) {
        print("应用进入后台，确保播放状态正确")
        DispatchQueue.main.async {
            self.synchronizePlaybackState(force: true)
        }
    }
}

// 扩展以提供路由变化原因的可读描述
extension AVAudioSession.RouteChangeReason {
    var description: String {
        switch self {
        case .unknown: return "unknown"
        case .newDeviceAvailable: return "newDeviceAvailable"
        case .oldDeviceUnavailable: return "oldDeviceUnavailable"
        case .categoryChange: return "categoryChange"
        case .override: return "override"
        case .wakeFromSleep: return "wakeFromSleep"
        case .noSuitableRouteForCategory: return "noSuitableRouteForCategory"
        case .routeConfigurationChange: return "routeConfigurationChange"
        @unknown default: return "未知原因"
        }
    }
} 