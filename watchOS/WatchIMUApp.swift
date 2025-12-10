import SwiftUI
import WatchConnectivity

@main
struct WatchIMUApp: App {
    init() { _ = WatchIMUManager.shared } // 세션/매니저 활성화
    var body: some Scene {
        WindowGroup {
            WatchContentView()
        }
    }
}
