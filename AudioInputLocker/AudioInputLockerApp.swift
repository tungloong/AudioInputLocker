import SwiftUI

@main
struct AudioInputLockerApp: App {
    @StateObject private var viewModel = AudioInputViewModel()

    var body: some Scene {
        MenuBarExtra {
            SoundMenuView(viewModel: viewModel)
        } label: {
            Label("Sound", image: viewModel.menuBarIconName)
        }
        .menuBarExtraStyle(.window)
    }
}
