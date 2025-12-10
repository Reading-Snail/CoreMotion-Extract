import Foundation

final class CSVExporter {
    static let shared = CSVExporter()
    private init() {}

    private let q = DispatchQueue(label: "imu.csv.queue")
    private var fileURL: URL?
    private var handle: FileHandle?
    private(set) var currentSessionId: String?

    func beginNewFile(sessionId: String,
                      header: String = "device_id,unix_timestamp,sensor_timestamp,accel_x,accel_y,accel_z,quart_x,quart_y,quart_z,quart_w,roll,pitch,yaw\n"
        ) {
        q.sync {
            closeUnlocked()

            currentSessionId = sessionId

            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd_HHmmss"
            let name = "IMU_\(df.string(from: Date()))_\(sessionId).csv"

            let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let url = dir.appendingPathComponent(name)

            // 파일 생성 + 헤더 작성
            do {
                if !FileManager.default.fileExists(atPath: url.path) {
                    try header.data(using: .utf8)?.write(to: url, options: .atomic)
                }
                self.fileURL = url
                self.handle = try FileHandle(forWritingTo: url)
                if #available(iOS 13.0, *) {
                    try self.handle?.seekToEnd()
                } else {
                    self.handle?.seekToEndOfFile()
                }
            } catch {
                print("[CSVExporter] open failed:", error)
                self.handle = nil
            }
        }
    }

    func append(batch: IMUBatch) {
        q.async {
            // (선택) 세션ID 필터링: 현재 세션과 다르면 무시
            if let cur = self.currentSessionId, cur != batch.sessionId {
                #if DEBUG
                print("[CSVExporter] skip batch (session mismatch): cur=\(cur), in=\(batch.sessionId)")
                #endif
                return
            }
            guard let h = self.handle else { return }

            var s = ""
            s.reserveCapacity(max(1, batch.samples.count) * 80)

            @inline(__always) func f(_ v: Double) -> String { String(format: "%.6f", v) }
            for x in batch.samples {
                s += "\(x.device_id)," +
                     "\(f(x.unix_timestamp)),\(f(x.sensor_timestamp))," +
                     "\(f(x.accel_x)),\(f(x.accel_y)),\(f(x.accel_z))," +
                     "\(f(x.quart_x)),\(f(x.quart_y)),\(f(x.quart_z)),\(f(x.quart_w))," +
                     "\(f(x.roll)),\(f(x.pitch)),\(f(x.yaw))\n"
            }
            if let d = s.data(using: .utf8) {
                if #available(iOS 13.0, *) {
                    do { try h.write(contentsOf: d) }  // throws
                    catch { print("[CSVExporter] write failed:", error) }
                } else {
                    h.write(d) // old API
                }
            }

            if batch.isFinal {
                self.closeUnlocked()
            }
        }
    }

    func currentFileURL() -> URL? { q.sync { fileURL } }

    func closeIfNeeded() { q.sync { closeUnlocked() } }

    private func closeUnlocked() {
        currentSessionId = nil
        guard let h = handle else { return }
        if #available(iOS 13.0, *) {
            do { try h.close() } catch { print("[CSVExporter] close failed:", error) }
        } else {
            h.closeFile()
        }
        handle = nil
    }
}
