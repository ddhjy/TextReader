import AVFoundation
import MediaPlayer

class AudioSessionManager {

    func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetooth])
            try session.setActive(true)
            print("Audio session configured for playback.")
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }

    func setupRemoteCommandCenter(playAction: @escaping () -> Void,
                                  pauseAction: @escaping () -> Void,
                                  nextAction: (() -> Void)? = nil,
                                  previousAction: (() -> Void)? = nil) {
        let commandCenter = MPRemoteCommandCenter.shared()

        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { _ in
            playAction()
            return .success
        }

        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { _ in
            pauseAction()
            return .success
        }

        // Optional: Enable and handle next/previous commands if needed
        if let next = nextAction {
            commandCenter.nextTrackCommand.isEnabled = true
            commandCenter.nextTrackCommand.addTarget { _ in next(); return .success }
        } else {
            commandCenter.nextTrackCommand.isEnabled = false
        }

        if let prev = previousAction {
            commandCenter.previousTrackCommand.isEnabled = true
            commandCenter.previousTrackCommand.addTarget { _ in prev(); return .success }
        } else {
            commandCenter.previousTrackCommand.isEnabled = false
        }

        // Optional: Handle other commands like seek, skip, change playback rate etc.
        print("Remote command center configured.")
    }

    func updateNowPlayingInfo(title: String?, isPlaying: Bool, currentPage: Int? = nil, totalPages: Int? = nil) {
        var nowPlayingInfo: [String: Any] = [:]
        nowPlayingInfo[MPMediaItemPropertyTitle] = title ?? "TextReader"
        nowPlayingInfo[MPMediaItemPropertyArtist] = "TextReader App" // Or specific author if available
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0

        if let current = currentPage, let total = totalPages, total > 0 {
            // Provide playback progress if available
            // Note: Duration/Elapsed time might not be the best fit for page numbers.
            // Using chapter data might be more appropriate if supported by controls.
            nowPlayingInfo[MPNowPlayingInfoPropertyChapterNumber] = current
            nowPlayingInfo[MPNowPlayingInfoPropertyChapterCount] = total
            // Alternatively, set a dummy duration and map pages to time? (less ideal)
            // nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = TimeInterval(total)
            // nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = TimeInterval(current - 1)
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }

    func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
} 