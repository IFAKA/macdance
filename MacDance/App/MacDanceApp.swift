import SwiftUI

@main
struct MacDanceApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("MacDance", id: "main") {
            RootView()
                .environment(appState)
                .frame(minWidth: 1024, minHeight: 768)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
