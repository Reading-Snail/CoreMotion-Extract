import SwiftUI

struct WatchContentView: View {
    @StateObject private var mgr = WatchIMUManager.shared
    var body: some View {
        VStack(spacing: 6) {
            Text("📡 Watch IMU")
            Text(String(format: "Acc  %.3f %.3f %.3f", mgr.accel_x, mgr.accel_y, mgr.accel_z))
            Text(String(format: "Quart %.3f %.3f %.3f %.3f", mgr.quart_x, mgr.quart_y, mgr.quart_z, mgr.quart_w))
            Text(mgr.isCollecting ? "수집 중…" : "대기")
                .foregroundStyle(mgr.isCollecting ? .green : .secondary)
        }
        .padding()
    }
}
