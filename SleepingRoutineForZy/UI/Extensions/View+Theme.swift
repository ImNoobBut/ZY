import SwiftUI

extension View {
    func nightScreen() -> some View {
        self
            .background(NightSkyBackground())
            .foregroundStyle(AppTheme.primaryText)
    }
}

extension TimeInterval {
    var mmssCountdown: String {
        let total = max(0, Int(self.rounded()))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
