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
        // Audio session interruption notification
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleAudioSessionInterruption), 
            name: AVAudioSession.interruptionNotification, 
            object: nil
        )
        
        // Audio route change notification
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleAudioRouteChange), 
            name: AVAudioSession.routeChangeNotification, 
            object: nil
        )
        
        // App state notification, handles sync when returning from background
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(handleAppDidBecomeActive), 
            name: UIApplication.didBecomeActiveNotification, 
            object: nil
        )
        
        // App entered background notification
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
            
            // Ensure control center state is correct upon initialization
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
        // Clear any existing targets to avoid adding duplicates
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
        // If the state is stopped, first try to clear existing info to ensure control center refreshes state
        if !isPlaying {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
        
        // Set new info after a short delay to ensure clear operation is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            var nowPlayingInfo: [String: Any] = [:]
            nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? "TextReader"
            nowPlayingInfo[MPMediaItemPropertyArtist] = "TextReader App"
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
            
            nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
            
            // Add a small virtual playback duration and progress to help control center recognize the state better
            let fakeDuration = 3600.0 // 1 hour
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = fakeDuration
            
            if let current = currentPage, let total = totalPages, total > 0 {
                nowPlayingInfo[MPNowPlayingInfoPropertyChapterNumber] = current
                nowPlayingInfo[MPNowPlayingInfoPropertyChapterCount] = total
                
                // Set playback progress based on page number
                let progress = Double(current) / Double(total)
                nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = fakeDuration * progress
            }
            
            // Update our internal record of the system playback state
            self.isSystemPlaybackActive = isPlaying
            
            print("Updating NowPlayingInfo: \(isPlaying ? "PLAYING" : "PAUSED") - Force update")
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            
            // If playback is stopped, additionally try to make the system recognize the stopped state
            if !isPlaying {
                self.forceSystemToRecognizePausedState()
            }
            
            // Ensure audio session state is consistent with playback state
            self.updateAudioSessionIfNeeded(isPlaying: isPlaying)
        }
    }
    
    /// Attempts to force the system (Control Center, Lock Screen) to recognize the paused state.
    private func forceSystemToRecognizePausedState() {
        do {
            // Temporarily deactivate then reactivate audio session to help system recognize state change
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            try AVAudioSession.sharedInstance().setActive(true, options: [])
            isAudioSessionActive = true
            
            // Clear and reset remote control center
            let commandCenter = MPRemoteCommandCenter.shared()
            commandCenter.playCommand.isEnabled = true
            commandCenter.pauseCommand.isEnabled = false // Temporarily disable pause command
            
            // Set normal state after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                commandCenter.pauseCommand.isEnabled = true
                commandCenter.playCommand.isEnabled = true
            }
        } catch {
            print("Failed to force system to recognize paused state: \(error)")
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
        
        // Set new info after a short delay to ensure clear operation is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        }
    }
    
    /// Synchronizes the app's internal playback state with the Now Playing info, especially when discrepancies are detected or forced.
    func synchronizePlaybackState(force: Bool = false) {
        guard let viewModel = contentViewModel else { return }
        
        let isUIPlaying = viewModel.isReading
        
        // Only synchronize when state is inconsistent or forced
        if force || isUIPlaying != isSystemPlaybackActive {
            print("Synchronizing playback state - UI: \(isUIPlaying), System: \(isSystemPlaybackActive)")
            
            // Use UI state as true state
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
        
        print("Audio interruption: \(type == .began ? "began" : "ended")")
        
        switch type {
        case .began:
            // Interruption began, e.g., phone call or other app starting audio playback
            isAudioSessionActive = false
            
            // If playing, immediately pause and update state
            if let viewModel = contentViewModel, viewModel.isReading {
                DispatchQueue.main.async {
                    // Ensure system state is updated before calling pause method
                    self.isSystemPlaybackActive = false
                    viewModel.stopReading()
                }
            }
            
        case .ended:
            // Interruption ended
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                
                // Try to reactivate audio session
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    isAudioSessionActive = true
                    
                    // If system indicates should resume playback and UI indicates should be in playback state, resume playback
                    if options.contains(.shouldResume) && contentViewModel?.isReading == true {
                        // Should only resume when user explicitly indicates they want to resume
                        print("System indicates can resume playback, but this app lets user decide whether to resume")
                    }
                    
                    // Regardless, ensure system state is consistent with app state
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
        
        print("Audio route change: \(reason.description)")
        
        switch reason {
        case .oldDeviceUnavailable:
            // E.g., unplugging headphones pauses playback
            if let viewModel = contentViewModel, viewModel.isReading {
                DispatchQueue.main.async {
                    self.isSystemPlaybackActive = false
                    viewModel.stopReading()
                }
            }
        case .newDeviceAvailable, .categoryChange:
            // New device connection or category change ensures state consistent
            DispatchQueue.main.async {
                self.synchronizePlaybackState()
            }
        default:
            // Other cases also ensure state consistent
            DispatchQueue.main.async {
                self.synchronizePlaybackState()
            }
        }
    }
    
    /// Synchronizes playback state when the app becomes active.
    @objc private func handleAppDidBecomeActive(notification: Notification) {
        print("App became active, synchronizing playback state")
        DispatchQueue.main.async {
            self.synchronizePlaybackState(force: true)
        }
    }
    
    /// Ensures the Now Playing info is correctly updated when the app enters the background.
    @objc private func handleAppDidEnterBackground(notification: Notification) {
        print("App entered background, ensuring playback state correct")
        DispatchQueue.main.async {
            self.synchronizePlaybackState(force: true)
        }
    }
}

// Extension to provide readable description of route change reason
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
        @unknown default: return "Unknown reason"
        }
    }
} 