import AVFoundation
import MediaPlayer

/// 音频会话管理器，负责处理音频相关的系统交互
///
/// 该类管理以下功能：
/// - 音频会话的配置和激活
/// - 控制中心的媒体信息显示
/// - 音频中断处理（如电话呼入）
/// - 音频路由变化处理（如耳机插拔）
/// - 远程控制命令的响应（如锁屏界面的播放/暂停按钮）
class AudioSessionManager: NSObject {
    /// 内容视图模型的弱引用，用于状态同步和回调
    private weak var contentViewModel: ContentViewModel?
    /// 音频会话当前是否处于激活状态
    private var isAudioSessionActive = false
    
    /// 跟踪系统播放状态，确保与系统事件（远程命令、中断）保持一致
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
    
    /// 设置音频会话相关通知的观察者，包括中断和路由变化等
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
        
        // 应用进入前台通知，处理从后台返回时的状态同步
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
    
    /// 注册内容视图模型，以便在音频事件发生时进行回调
    /// - Parameter viewModel: 内容视图模型
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
    /// - Parameters:
    ///   - playAction: 播放按钮触发的操作
    ///   - pauseAction: 暂停按钮触发的操作
    ///   - nextAction: 下一曲按钮触发的操作，可选
    ///   - previousAction: 上一曲按钮触发的操作，可选
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

    /// 更新控制中心的媒体信息，包括标题、播放状态和页码
    /// - Parameters:
    ///   - title: 当前书籍标题
    ///   - isPlaying: 是否正在播放
    ///   - currentPage: 当前页码
    ///   - totalPages: 总页数
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
            self.updateAudioSessionIfNeeded(isPlaying: isPlaying)
        }
    }
    
    /// 尝试强制系统（控制中心、锁屏）识别暂停状态
    private func forceSystemToRecognizePausedState() {
        do {
            // 临时停用然后重新激活音频会话，帮助系统识别状态变化
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            isAudioSessionActive = true
            
            // 清除并重置远程控制中心
            let commandCenter = MPRemoteCommandCenter.shared()
            commandCenter.playCommand.isEnabled = true
            commandCenter.pauseCommand.isEnabled = false // 暂时禁用暂停命令
            
            // 短暂延迟后恢复正常状态
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                commandCenter.pauseCommand.isEnabled = true
                commandCenter.playCommand.isEnabled = true
            }
        } catch {
            print("强制系统识别暂停状态失败: \(error)")
        }
    }

    /// 确保只有在预期播放时音频会话才处于活跃状态
    /// - Parameter isPlaying: 是否正在播放
    private func updateAudioSessionIfNeeded(isPlaying: Bool) {
        if isPlaying && !isAudioSessionActive {
            do {
                try AVAudioSession.sharedInstance().setActive(true, options: [])
                isAudioSessionActive = true
                print("已为播放重新激活音频会话")
            } catch {
                print("激活音频会话失败: \(error)")
            }
        }
    }

    /// 清除控制中心的媒体信息
    func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        isSystemPlaybackActive = false
        
        // 短暂延迟后再次清除，确保操作完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }
    
    /// 同步应用内部播放状态与控制中心显示状态，特别是当检测到不一致或被强制同步时
    /// - Parameter force: 是否强制同步，无论状态是否一致
    func synchronizePlaybackState(force: Bool = false) {
        guard let viewModel = contentViewModel else { return }
        
        let isUIPlaying = viewModel.isReading
        
        // 只有在状态不一致或强制同步时才执行同步
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
    
    /// 处理音频会话中断（如电话呼入）
    /// - Parameter notification: 中断通知
    @objc private func handleAudioSessionInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        print("音频中断: \(type == .began ? "开始" : "结束")")
        
        switch type {
        case .began:
            // 中断开始，如电话呼入或其他应用开始音频播放
            isAudioSessionActive = false
            
            // 如果正在播放，立即暂停并更新状态
            if let viewModel = contentViewModel, viewModel.isReading {
                DispatchQueue.main.async {
                    // 确保在调用暂停方法前更新系统状态
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
                    
                    // 如果系统指示应该恢复播放且UI指示应该处于播放状态，则恢复播放
                    if options.contains(.shouldResume) && contentViewModel?.isReading == true {
                        // 仅当用户明确表示想要恢复时才应恢复
                        print("系统指示可以恢复播放，但本应用让用户决定是否恢复")
                    }
                    
                    // 无论如何，确保系统状态与应用状态一致
                    DispatchQueue.main.async {
                        self.synchronizePlaybackState()
                    }
                } catch {
                    print("重新激活音频会话失败: \(error)")
                }
            }
            
        @unknown default:
            print("未知的音频会话中断类型")
        }
    }
    
    /// 处理音频路由变化（如耳机拔出）
    /// - Parameter notification: 路由变化通知
    @objc private func handleAudioRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        print("音频路由变化: \(reason.description)")
        
        switch reason {
        case .oldDeviceUnavailable:
            // 例如，拔出耳机时暂停播放
            if let viewModel = contentViewModel, viewModel.isReading {
                DispatchQueue.main.async {
                    self.isSystemPlaybackActive = false
                    viewModel.stopReading()
                }
            }
        case .newDeviceAvailable, .categoryChange:
            // 新设备连接或类别更改时确保状态一致
            DispatchQueue.main.async {
                self.synchronizePlaybackState()
            }
        default:
            // 其他情况也确保状态一致
            DispatchQueue.main.async {
                self.synchronizePlaybackState()
            }
        }
    }
    
    /// 应用变为活跃状态时同步播放状态
    /// - Parameter notification: 应用变为活跃通知
    @objc private func handleAppDidBecomeActive(notification: Notification) {
        print("应用变为活跃状态，同步播放状态")
        DispatchQueue.main.async {
            self.synchronizePlaybackState(force: true)
        }
    }
    
    /// 确保应用进入后台时正确更新控制中心信息
    /// - Parameter notification: 应用进入后台通知
    @objc private func handleAppDidEnterBackground(notification: Notification) {
        print("应用进入后台，确保播放状态正确")
        DispatchQueue.main.async {
            self.synchronizePlaybackState(force: true)
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