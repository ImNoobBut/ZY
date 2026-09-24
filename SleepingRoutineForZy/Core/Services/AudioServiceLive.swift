import AVFoundation
import Foundation

protocol AudioService: AnyObject {
    var isPlaying: Bool { get }
    /// True while the audio session is interrupted (e.g. phone call).
    var isInterrupted: Bool { get }

    func prepare() throws
    func play() throws
    func pause()
    func stop()

    /// Called on the main actor when an interruption begins.
    var onInterruptionBegan: (() -> Void)? { get set }
    /// Called on the main actor when an interruption ends.
    var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)? { get set }
    /// Called on the main actor after an audio route change (headphones, Bluetooth, etc.).
    var onRouteChanged: ((_ shouldPause: Bool) -> Void)? { get set }
}

/// In-memory stub for previews and unit tests.
final class AudioServiceStub: AudioService {
    private(set) var isPlaying = false
    private(set) var isInterrupted = false
    private(set) var prepareCallCount = 0
    private(set) var playCallCount = 0
    private(set) var stopCallCount = 0

    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?
    var onRouteChanged: ((Bool) -> Void)?

    var shouldFailPrepare = false
    var shouldFailPlay = false

    func prepare() throws {
        prepareCallCount += 1
        if shouldFailPrepare { throw SleepRoutineError.audioSessionUnavailable }
    }

    func play() throws {
        playCallCount += 1
        if shouldFailPlay { throw SleepRoutineError.audioSessionUnavailable }
        isPlaying = true
        isInterrupted = false
    }

    func pause() {
        isPlaying = false
    }

    func stop() {
        stopCallCount += 1
        isPlaying = false
        isInterrupted = false
    }

    func simulateInterruptionBegan() {
        isInterrupted = true
        isPlaying = false
        onInterruptionBegan?()
    }

    func simulateInterruptionEnded(shouldResume: Bool) {
        isInterrupted = false
        onInterruptionEnded?(shouldResume)
    }

    func simulateRouteChange(shouldPause: Bool) {
        if shouldPause {
            isPlaying = false
        }
        onRouteChanged?(shouldPause)
    }
}

/// Plays soft looping app-owned audio via AVAudioSession + AVAudioPlayer.
/// Does not control Spotify or other apps' audio.
final class AudioServiceLive: NSObject, AudioService, AVAudioPlayerDelegate {
    private(set) var isPlaying = false
    private(set) var isInterrupted = false

    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?
    var onRouteChanged: ((Bool) -> Void)?

    private var player: AVAudioPlayer?
    private var sampleURL: URL?
    private var observers: [NSObjectProtocol] = []
    private var shouldResumeAfterInterruption = false
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
        super.init()
        registerSessionObservers()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        player?.stop()
    }

    func prepare() throws {
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setActive(true, options: [])
        } catch {
            throw SleepRoutineError.audioSessionUnavailable
        }

        if player == nil {
            let url = try Self.ensureSampleFile()
            sampleURL = url
            do {
                let audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer.numberOfLoops = -1
                audioPlayer.volume = 0.35
                audioPlayer.delegate = self
                audioPlayer.prepareToPlay()
                player = audioPlayer
            } catch {
                throw SleepRoutineError.audioSessionUnavailable
            }
        }
    }

    func play() throws {
        if player == nil {
            try prepare()
        }
        guard let player else {
            throw SleepRoutineError.audioSessionUnavailable
        }
        do {
            try session.setActive(true, options: [])
        } catch {
            throw SleepRoutineError.audioSessionUnavailable
        }
        guard player.play() else {
            throw SleepRoutineError.audioSessionUnavailable
        }
        isPlaying = true
        isInterrupted = false
        shouldResumeAfterInterruption = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        shouldResumeAfterInterruption = false
        player?.stop()
        player?.currentTime = 0
        isPlaying = false
        isInterrupted = false
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Looping player should not finish; keep state consistent if it does.
        isPlaying = player.isPlaying
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
    }

    // MARK: - Session observers

    private func registerSessionObservers() {
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                self?.handleInterruption(notification)
            }
        )
        observers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                self?.handleRouteChange(notification)
            }
        )
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            isInterrupted = true
            isPlaying = false
            onInterruptionBegan?()
        case .ended:
            isInterrupted = false
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            let shouldResume = options.contains(.shouldResume) && shouldResumeAfterInterruption
            // Routine layer decides whether to resume so state machine stays authoritative.
            onInterruptionEnded?(shouldResume)
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones / Bluetooth disconnected — pause app audio; do not claim to stop other apps.
            pause()
            onRouteChanged?(true)
        case .newDeviceAvailable, .categoryChange, .override, .wakeFromSleep,
             .noSuitableRouteForCategory, .routeConfigurationChange:
            onRouteChanged?(false)
        @unknown default:
            onRouteChanged?(false)
        }
    }

    private static func ensureSampleFile() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("quiet_night_tone.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            let data = SleepAudioSampleFactory.makeSoftToneWAV()
            try data.write(to: url, options: .atomic)
        }
        return url
    }
}
