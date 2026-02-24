import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.currentScreen {
            case .emptyLibrary:
                EmptyLibraryView()
            case .library:
                LibraryView()
            case .generating(let song):
                GeneratingView(songID: song.id)
            case .calibration(let song):
                CalibrationView(song: song)
            case .game(let song):
                GameView(song: song)
            case .result(let song, let score, let maxCombo):
                ResultView(song: song, score: score, maxCombo: maxCombo)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
