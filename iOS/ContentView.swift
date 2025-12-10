import SwiftUI
import CoreMotion

struct ContentView: View {
    @StateObject private var imu = PhoneIMU()
    @State private var savedURL: URL?

    var body: some View {
        VStack(spacing: 12) {

            Text("📱 iPhone + ⌚️ Watch IMU")
                .font(.title3).bold()

            // 🔵 연결 상태 배지
            HStack(spacing: 8) {
                statusPill(icon: "applewatch", title: "Watch",
                           ok: imu.isWatchConnected,
                           okText: "연결됨", failText: "미연결")

                statusPill(icon: "airpodspro", title: "AirPods",
                           ok: imu.isAirPodsConnected,
                           okText: "연결됨", failText: "미연결")

                Button {
                    imu.refreshStatuses()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("상태 새로고침")
            }

            // 🟣 iPhone 위치 토글 (Left / Right)
            HStack(spacing: 10) {
                Image(systemName: "iphone.gen2")
                Toggle(isOn: $imu.iphoneIsLeft) {
                    Text(imu.iphoneIsLeft ? "iPhone 위치: 왼쪽" : "iPhone 위치: 오른쪽")
                        .font(.footnote.weight(.semibold))
                }
                .disabled(imu.isCollecting) // 수집 중 변경 방지(원하면 제거)
            }
            .padding(.vertical, 4)

            Group {
                Text(String(format: "iPhone Acc  X: %.3f  Y: %.3f  Z: %.3f", imu.accel_x, imu.accel_y, imu.accel_z))
                Text(String(format: "iPhone Quart X: %.3f  Y: %.3f  Z: %.3f  W: %.3f", imu.quart_x, imu.quart_y, imu.quart_z, imu.quart_w))
            }
            .font(.system(.body, design: .monospaced))

            HStack {
                Button {
                    imu.startCollection()
                } label: { Label("시작", systemImage: "play.fill") }
                .buttonStyle(.borderedProminent)
                .disabled(imu.isCollecting)

                Button {
                    imu.stopCollection()
                    savedURL = CSVExporter.shared.currentFileURL()
                } label: { Label("종료 & 저장", systemImage: "stop.fill") }
                .buttonStyle(.bordered)
                .disabled(!imu.isCollecting)
            }

            if let url = savedURL {
                ShareLink(item: url) { Label("CSV 공유", systemImage: "square.and.arrow.up") }
                Text("파일: \(url.lastPathComponent)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(imu.isCollecting ? "상태: 수집 중…" : "상태: 대기")
                .foregroundStyle(imu.isCollecting ? .green : .secondary)
        }
        .padding()
    }

    // MARK: - Small UI helper
    @ViewBuilder
    private func statusPill(icon: String, title: String, ok: Bool, okText: String, failText: String) -> some View {
        Label {
            Text("\(title) \(ok ? okText : failText)")
        } icon: {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background((ok ? Color.green.opacity(0.15) : Color.red.opacity(0.15)), in: Capsule())
        .overlay(
            HStack(spacing: 3) {
                Image(systemName: icon).font(.footnote)
                Color.clear.frame(width: 0) // layout shim
            }
            .padding(.leading, 8)
            .opacity(0.8),
            alignment: .leading
        )
    }
}
