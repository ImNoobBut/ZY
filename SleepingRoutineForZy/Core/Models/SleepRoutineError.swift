import Foundation

enum SleepRoutineError: LocalizedError, Equatable {
    case spotifyNotConnected
    case spotifyPlaybackUnavailable
    case notificationPermissionDenied
    case alarmSchedulingFailed
    case audioSessionUnavailable
    case authenticationFailed
    case networkUnavailable
    case keychainUnavailable
    case persistenceFailed
    case invalidRoutineTransition(from: RoutineState, to: RoutineState)
    case customTimerOutOfRange
    case adminNotOptedIn
    case adminPINInvalid
    case adminPINIncorrect
    case adminNotRegistered
    case adminBackendUnavailable

    var errorDescription: String? {
        switch self {
        case .spotifyNotConnected:
            return String(localized: "error.spotify_not_connected", defaultValue: "Spotify needs to be connected again.")
        case .spotifyPlaybackUnavailable:
            return String(
                localized: "error.spotify_playback_unavailable",
                defaultValue: "Spotify playback isn't available right now. Please open Spotify to continue."
            )
        case .notificationPermissionDenied:
            return String(
                localized: "error.notification_permission_denied",
                defaultValue: "Alarm permission is turned off. Wake alarms need access to work."
            )
        case .alarmSchedulingFailed:
            return String(localized: "error.alarm_scheduling_failed", defaultValue: "We couldn't schedule that alarm. Please try again.")
        case .audioSessionUnavailable:
            return String(localized: "error.audio_session_unavailable", defaultValue: "Audio isn't available right now.")
        case .authenticationFailed:
            return String(localized: "error.authentication_failed", defaultValue: "Sign-in didn't work. Please try again.")
        case .networkUnavailable:
            return String(localized: "error.network_unavailable", defaultValue: "You're offline. Check your connection and try again.")
        case .keychainUnavailable:
            return String(localized: "error.keychain_unavailable", defaultValue: "Secure storage isn't available on this device.")
        case .persistenceFailed:
            return String(localized: "error.persistence_failed", defaultValue: "We couldn't save your settings. Please try again.")
        case .invalidRoutineTransition(let from, let to):
            return String(
                localized: "error.invalid_routine_transition",
                defaultValue: "That action isn't available in the current sleep routine state (\(from.rawValue) → \(to.rawValue))."
            )
        case .customTimerOutOfRange:
            return String(
                localized: "error.custom_timer_out_of_range",
                defaultValue: "Choose a sleep timer between 1 and 180 minutes."
            )
        case .adminNotOptedIn:
            return String(
                localized: "error.admin_not_opted_in",
                defaultValue: "Remote monitoring is off. Turn it on in Admin to share status."
            )
        case .adminPINInvalid:
            return String(
                localized: "error.admin_pin_invalid",
                defaultValue: "Choose a 4–8 digit PIN."
            )
        case .adminPINIncorrect:
            return String(
                localized: "error.admin_pin_incorrect",
                defaultValue: "That PIN didn't match. Try again."
            )
        case .adminNotRegistered:
            return String(
                localized: "error.admin_not_registered",
                defaultValue: "This phone isn't registered with the Admin backend yet."
            )
        case .adminBackendUnavailable:
            return String(
                localized: "error.admin_backend_unavailable",
                defaultValue: "The Admin backend isn't reachable. Check BACKEND_BASE_URL and that the server is running."
            )
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .spotifyNotConnected:
            return String(localized: "error.recovery.reconnect_spotify", defaultValue: "Reconnect Spotify")
        case .spotifyPlaybackUnavailable:
            return String(localized: "error.recovery.open_spotify", defaultValue: "Open Spotify")
        case .notificationPermissionDenied:
            return String(localized: "error.recovery.open_settings", defaultValue: "Open Settings")
        case .networkUnavailable, .authenticationFailed, .alarmSchedulingFailed, .persistenceFailed,
             .adminBackendUnavailable, .adminPINIncorrect:
            return String(localized: "error.recovery.try_again", defaultValue: "Try again")
        case .adminNotOptedIn:
            return String(localized: "error.recovery.open_admin", defaultValue: "Open Admin")
        default:
            return nil
        }
    }
}
