import AVFoundation
import Foundation

protocol AudioService: AnyObject {
    var isPlaying: Bool { get }
    /// True while the audio session is interrupted (e.g. phone call).
    var isInterrupted: Bool { get }
    var isFading: Bool { get }

    func prepare(sound: QuietSound) throws
    func play() throws
    func pause()
    func stop()
    func fadeOut(over duration: TimeInterval)

    /// Called on the main actor when an interruption begins.
    var onInterruptionBegan: (() -> Void)? { get set }
    /// Called on the main actor when an interruption ends.
    var onInterruptionEnded: ((_ shouldResume: Bool) -> Void)? { get set }
    /// Called on the main actor after an audio route change (headphones, Bluetooth, etc.).
    var onRouteChanged: ((_ shouldPause: Bool) -> Void)? { get set }
}

extension AudioService {
    func prepare() throws {
        try prepare(sound: .softTone)
    }
}

/// In-memory stub for previews and unit tests.
final class AudioServiceStub: AudioService {
    private(set) var isPlaying = false
    private(set) var isInterrupted = false
    private(set) var isFading = false
    private(set) var prepareCallCount = 0
    private(set) var playCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var fadeOutCallCount = 0

    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?
    var onRouteChanged: ((Bool) -> Void)?

    var shouldFailPrepare = false
    var shouldFailPlay = false

    func prepare(sound: QuietSound) throws {
        prepareCallCount += 1
        if shouldFailPrepare { throw SleepRoutineError.audioSessionUnavailable }
    }

    func play() throws {
        playCallCount += 1
        if shouldFailPlay { throw SleepRoutineError.audioSessionUnavailable }
        isPlaying = true
        isInterrupted = false
        isFading = false
    }

    func pause() {
        isPlaying = false
    }

    func stop() {
        stopCallCount += 1
        isPlaying = false
        isInterrupted = false
        isFading = false
    }

    func fadeOut(over duration: TimeInterval) {
        fadeOutCallCount += 1
        isFading = true
        isPlaying = false
        isFading = false
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
    private(set) var isFading = false

    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)?
    var onRouteChanged: ((Bool) -> Void)?

    private var player: AVAudioPlayer?
    private var sampleURL: URL?
    private var currentSound: QuietSound = .softTone
    private var observers: [NSObjectProtocol] = []
    private var shouldResumeAfterInterruption = false
    private var fadeTask: Task<Void, Never>?
    private let session: AVAudioSession
    private let baseVolume: Float = 0.35

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
        super.init()
        registerSessionObservers()
    }

    deinit {
        fadeTask?.cancel()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        player?.stop()
    }

    func prepare(sound: QuietSound) throws {
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

        if player == nil || currentSound != sound {
            player?.stop()
            let url = try Self.ensureSampleFile(for: sound)
            sampleURL = url
            currentSound = sound
            do {
                let audioPlayer = try AVAudioPlayer(contentsOf: url)
                audioPlayer.numberOfLoops = -1
                audioPlayer.volume = baseVolume
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
            try prepare(sound: currentSound)
        }
        guard let player else {
            throw SleepRoutineError.audioSessionUnavailable
        }
        cancelFade()
        player.volume = baseVolume
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
        cancelFade()
        player?.pause()
        isPlaying = false
    }

    func stop() {
        cancelFade()
        shouldResumeAfterInterruption = false
        player?.stop()
        player?.currentTime = 0
        player?.volume = baseVolume
        isPlaying = false
        isInterrupted = false
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func fadeOut(over duration: TimeInterval) {
        guard isPlaying, !isFading, let player else { return }
        cancelFade()
        isFading = true
        let startVolume = player.volume
        let steps = max(1, Int(duration / 0.25))
        fadeTask = Task { @MainActor in
            for step in 1...steps {
                if Task.isCancelled { return }
                let t = Float(step) / Float(steps)
                player.volume = startVolume * (1 - t)
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            if !Task.isCancelled {
                self.stop()
            }
        }
    }

    private func cancelFade() {
        fadeTask?.cancel()
        fadeTask = nil
        isFading = false
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = player.isPlaying
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        isPlaying = false
    }

    // MARK: - Session observers

    private func registerSessionObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        })
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        })
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
            pause()
            onRouteChanged?(true)
        case .newDeviceAvailable, .categoryChange, .override, .wakeFromSleep,
             .noSuitableRouteForCategory, .routeConfigurationChange:
            onRouteChanged?(false)
        @unknown default:
            onRouteChanged?(false)
        }
    }

    private static func ensureSampleFile(for sound: QuietSound) throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("zy_quiet_\(sound.rawValue).wav")
        let data = SleepAudioSampleFactory.makeWAV(for: sound)
        try data.write(to: url, options: .atomic)
        return url
    }
}
