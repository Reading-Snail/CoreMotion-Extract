import SwiftUI

@main
struct IMUCollectorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    _ = PhoneSession.shared // 세션 활성화
                }
        }
    }
}
