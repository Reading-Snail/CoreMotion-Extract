import Foundation
import CoreMotion

public struct IMUSample: Codable {
    public let device_id: Int
    public let unix_timestamp: Double
    public let sensor_timestamp: Double
    public let accel_x: Double
    public let accel_y: Double
    public let accel_z: Double
    public let quart_x: Double
    public let quart_y: Double
    public let quart_z: Double
    public let quart_w: Double
    public let roll: Double
    public let pitch: Double
    public let yaw: Double

    // iPhone(DeviceMotion) 전용 팩토리
    public static func fromDeviceMotion(unix_ts: Double, dm: CMDeviceMotion, device_id: Int) -> IMUSample {
        let att = dm.attitude
        return IMUSample(
            device_id: device_id,
            unix_timestamp: unix_ts,
            sensor_timestamp: dm.timestamp,
            accel_x: dm.userAcceleration.x,
            accel_y: dm.userAcceleration.y,
            accel_z: dm.userAcceleration.z,
            quart_x: att.quaternion.x,
            quart_y: att.quaternion.y,
            quart_z: att.quaternion.z,
            quart_w: att.quaternion.w,
            roll: att.roll,
            pitch: att.pitch,
            yaw: att.yaw
        )
    }

    // 일부 소스(AirPods 등) → 없는 값은 NaN
    public static func partial(
        unix_ts: Double,
        sensor_ts: Double,
        device_id: Int,
        accel_x: Double?, accel_y: Double?, accel_z: Double?,
        quart_x: Double? = nil, quart_y: Double? = nil, quart_z: Double? = nil, quart_w: Double? = nil,
        roll: Double? = nil, pitch: Double? = nil, yaw: Double? = nil
    ) -> IMUSample {
        func n(_ v: Double?) -> Double { v ?? .nan }
        return IMUSample(
            device_id: device_id,
            unix_timestamp: unix_ts,
            sensor_timestamp: sensor_ts,
            accel_x: n(accel_x), accel_y: n(accel_y), accel_z: n(accel_z),
            quart_x: n(quart_x), quart_y: n(quart_y), quart_z: n(quart_z), quart_w: n(quart_w),
            roll: n(roll), pitch: n(pitch), yaw: n(yaw)
        )
    }
}

public struct IMUBatch: Codable {
    public let sessionId: String
    public let samples: [IMUSample]
    public let isFinal: Bool
}

public struct StartPayload: Codable {
    public let sessionId: String
    public let phoneWallAtT0: Double // Date().timeIntervalSince1970
}

public enum ControlMessage: String, Codable { case start, stop }

