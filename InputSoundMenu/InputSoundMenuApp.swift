import SwiftUI

@main
struct InputSoundMenuApp: App {
    @StateObject private var viewModel = AudioInputViewModel()

    var body: some Scene {
        MenuBarExtra("Sound", systemImage: "music.microphone") {
            SoundMenuView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
