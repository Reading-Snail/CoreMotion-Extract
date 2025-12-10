//import Foundation
//import WatchKit
//import WatchConnectivity
//import CoreMotion
//import Combine
//
//@MainActor
//final class WatchIMUManager: NSObject, ObservableObject {
//    static let shared = WatchIMUManager()
//    
//    override init() {
//        super.init()
//        if WCSession.isSupported() {
//            WCSession.default.delegate = self
//            WCSession.default.activate()
//        }
//    }
//    
//    @Published var accel_x = 0.0
//    @Published var accel_y = 0.0
//    @Published var accel_z = 0.0
//    
//    @Published var quart_x = 0.0
//    @Published var quart_y = 0.0
//    @Published var quart_z = 0.0
//    @Published var quart_w = 0.0
//    
//    @Published var isCollecting = false{
//        didSet {
//            if !isCollecting { resetDisplayedValues() }   // 👈 대기로 바뀌는 즉시 UI 0으로
//        }
//    }
//    
//    private func resetDisplayedValues() {
//        accel_x = 0
//        accel_y = 0
//        accel_z = 0
//        quart_x = 0
//        quart_y = 0
//        quart_z = 0
//        quart_w = 0
//    }
//    
//    private let motion = CMMotionManager()
//    private let interval = 1.0 / 100.0 // ✅ 100Hz
//    private var sessionId: String = ""
//    private var phoneWallAtT0: Double = 0.0
//    private var watchUptimeAtStart: TimeInterval = 0.0
//    
//    private var batch: [IMUSample] = []
//    private let batchSize = 20
//    private var session: WCSession? { WCSession.isSupported() ? .default : nil }
//
//
//    private func activate() {
//        session?.delegate = self
//        session?.activate()
//    }
//    
//    private func handleInbound(dict: [String: Any]) {
//        guard let typeRaw = dict["type"] as? String,
//              let type = ControlMessage(rawValue: typeRaw) else { return }
//
//        print("[WATCH] inbound type =", typeRaw)   // 🔎 디버그
//
//        switch type {
//        case .start:
//            if let data = dict["payload"] as? Data,
//               let payload = try? JSONDecoder().decode(StartPayload.self, from: data) {
//                handleStart(payload: payload)
//            }
//        case .stop:
//            handleStop()
//        }
//    }
//    
//    // MARK: - Start/Stop
//    // WatchIMUManager.handleStart(payload:)
//    private func handleStart(payload: StartPayload) {
//        sessionId = payload.sessionId
//        phoneWallAtT0 = payload.phoneWallAtT0
//        watchUptimeAtStart = ProcessInfo.processInfo.systemUptime
//
//        batch.removeAll(keepingCapacity: true)
//        isCollecting = true
//
//        // ✅ Accelerometer 제거 (DeviceMotion 하나만 사용)
//        if motion.isDeviceMotionAvailable {
//            motion.deviceMotionUpdateInterval = interval // 100 Hz
//            motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] dm, _ in
//                guard let self, let dm else { return }
//
//                // 화면 표시용
//                let att = dm.attitude
//                let q = att.quaternion
//                self.quart_x = q.x; self.quart_y = q.y; self.quart_z = q.z; self.quart_w = q.w
//                let ua = dm.userAcceleration
//                self.accel_x = ua.x; self.accel_y = ua.y; self.accel_z = ua.z
//
//                // ← 여기서 바로 샘플 생성 & 배치
//                self.appendSampleFromDeviceMotion(dm)
//            }
//        }
//    }
//    
//    // 새로 추가: DeviceMotion → 샘플 변환
//    private func appendSampleFromDeviceMotion(_ dm: CMDeviceMotion) {
//        guard isCollecting else { return }
//
//        // 시간 동기화 (폰 기준)
//        let nowUp = ProcessInfo.processInfo.systemUptime
//        let unixTs = phoneWallAtT0 + (nowUp - watchUptimeAtStart)
//
//        // 손목 기준 device_id
//        let wristLoc = WKInterfaceDevice.current().wristLocation
//        let watchDeviceId = (wristLoc == .left) ? 1 : 4  // Left_watch:1, Right_watch:4
//
//        // 값 구성
//        let att = dm.attitude
//        let q = att.quaternion
//        let ua = dm.userAcceleration
//        let sample = IMUSample(
//            device_id: watchDeviceId,
//            unix_timestamp: unixTs,
//            sensor_timestamp: dm.timestamp,
//            accel_x: ua.x, accel_y: ua.y, accel_z: ua.z,
//            quart_x: q.x, quart_y: q.y, quart_z: q.z, quart_w: q.w,
//            roll: att.roll, pitch: att.pitch, yaw: att.yaw
//        )
//
//        batch.append(sample)
//        if batch.count >= batchSize { flush(isFinal: false) }
//    }
//    
//    private func handleStop() {
//        guard isCollecting else { return }
//
//        // 1) 먼저 UI 상태 끄기 (메인 액터)
//        isCollecting = false
//        print("[WATCH] handleStop")
//
//        // 2) 모든 센서 중지
//        motion.stopAccelerometerUpdates()
//        motion.stopGyroUpdates()
//        motion.stopDeviceMotionUpdates()   // ✅ 빠져 있던 부분
//
//        // 3) 마지막 배치 전송
//        flush(isFinal: true)
//
//        // 4) 캐시 초기화(선택)
//        latestAcc = nil
//        latestGyro = nil
//        latestAttitude = nil
//        latestSensorTimestamp = nil
//    }
//
//    
//    // MARK: - Batching
//    private var latestAcc: (Double,Double,Double)?
//    private var latestGyro: (Double,Double,Double)?
//    private var latestAttitude: CMAttitude?
//    private var latestSensorTimestamp: Double?
//    
//    private func appendIfReady() {
//        guard isCollecting else { return }
//        guard let a = latestAcc else { return }
//
//        // 시간 동기화
//        let nowUptime = ProcessInfo.processInfo.systemUptime
//        let unixTs = phoneWallAtT0 + (nowUptime - watchUptimeAtStart)
//
//        // 착용 손목 감지로 device_id 자동 설정 (예: Left_watch=1, Right_watch=4)
//        let wristLoc = WKInterfaceDevice.current().wristLocation
//        let watchDeviceId = (wristLoc == .left) ? 1 : 4
//
//        // attitude가 있으면 값 채우고, 없으면 NaN
//        let (qx, qy, qz, qw, r, p, y): (Double, Double, Double, Double, Double, Double, Double)
//        if let att = latestAttitude {
//            let q = att.quaternion
//            qx = q.x; qy = q.y; qz = q.z; qw = q.w
//            r = att.roll; p = att.pitch; y = att.yaw
//        } else {
//            qx = .nan; qy = .nan; qz = .nan; qw = .nan
//            r = .nan;  p = .nan;  y = .nan
//        }
//
//        let sensorTs = latestSensorTimestamp ?? nowUptime
//
//        let sample = IMUSample(
//            device_id: watchDeviceId,
//            unix_timestamp: unixTs,
//            sensor_timestamp: sensorTs,
//            accel_x: a.0, accel_y: a.1, accel_z: a.2,
//            quart_x: qx,  quart_y: qy,  quart_z: qz,  quart_w: qw,
//            roll: r,      pitch: p,     yaw: y
//        )
//
//        batch.append(sample)
//        if batch.count >= batchSize { flush(isFinal: false) }
//    }
//
//    
//    // 예: flush 시점에 호출
//    private func flush(isFinal: Bool) {
//        guard !batch.isEmpty else { return }
//        print("[WATCH] flush count=\(batch.count), isFinal=\(isFinal)")
//        sendBatchToPhone(sessionId: sessionId, samples: batch, isFinal: isFinal)
//        batch.removeAll(keepingCapacity: true)
//    }
//    
//    // 배치가 찼을 때 호출되는 곳에서 전송
//    private func sendBatchToPhone(sessionId: String, samples: [IMUSample], isFinal: Bool) {
//        let batch = IMUBatch(sessionId: sessionId, samples: samples, isFinal: isFinal)
//        do {
//            let encoder = JSONEncoder()
//            encoder.nonConformingFloatEncodingStrategy = .convertToString(
//                positiveInfinity: "Infinity",
//                negativeInfinity: "-Infinity",
//                nan: "NaN"
//            )
//            let data = try encoder.encode(batch)
//
//            let s = WCSession.default
//            if s.isReachable {
//                s.sendMessageData(data, replyHandler: nil) { error in
//                    print("[Watch] sendMessageData error:", error)
//                }
//            } else {
//                s.transferUserInfo(["imuBatch": data])
//            }
//        } catch {
//            print("[Watch] encode IMUBatch error:", error)
//        }
//    }
//    
//}
//
//extension WatchIMUManager: WCSessionDelegate {
//
//    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
//        Task { @MainActor in
//            WatchIMUManager.shared.handleInbound(dict: message)
//        }
//    }
//
//    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
//        Task { @MainActor in
//            WatchIMUManager.shared.handleInbound(dict: userInfo)
//        }
//    }
//
//    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
//        Task { @MainActor in
//            WatchIMUManager.shared.handleInbound(dict: applicationContext)
//        }
//    }
//
//    nonisolated func session(_ session: WCSession,
//                             activationDidCompleteWith activationState: WCSessionActivationState,
//                             error: Error?) {
//        Task { @MainActor in
//            print("[WATCH] WC activated:", activationState.rawValue, "err:", String(describing: error))
//        }
//    }
//
//    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
//        Task { @MainActor in
//            print("[WATCH] reachabilityDidChange reachable=\(session.isReachable)")
//        }
//    }
//}

import Foundation
import WatchKit
import WatchConnectivity
import CoreMotion
import Combine

@MainActor
final class WatchIMUManager: NSObject, ObservableObject {
    static let shared = WatchIMUManager()
    
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // ==========================
    //  Published 상태값 (UI용)
    // ==========================
    @Published var accel_x = 0.0
    @Published var accel_y = 0.0
    @Published var accel_z = 0.0
    
    @Published var quart_x = 0.0
    @Published var quart_y = 0.0
    @Published var quart_z = 0.0
    @Published var quart_w = 0.0
    
    @Published var isCollecting = false {
        didSet {
            if !isCollecting { resetDisplayedValues() }
        }
    }
    
    private func resetDisplayedValues() {
        accel_x = 0
        accel_y = 0
        accel_z = 0
        quart_x = 0
        quart_y = 0
        quart_z = 0
        quart_w = 0
    }
    
    // ==========================
    // 센서 / 타이밍
    // ==========================
    private let motion = CMMotionManager()
    private let interval = 1.0 / 100.0     // 100 Hz
    private var sessionId: String = ""
    private var phoneWallAtT0: Double = 0.0
    private var watchUptimeAtStart: TimeInterval = 0.0
    
    // 배치 전송용
    private var batch: [IMUSample] = []
    private let batchSize = 20
    
    private var session: WCSession? {
        WCSession.isSupported() ? .default : nil
    }
    
    private func activate() {
        session?.delegate = self
        session?.activate()
    }
    
    // ==========================
    // 메시지 처리
    // ==========================
    private func handleInbound(dict: [String: Any]) {
        guard let typeRaw = dict["type"] as? String,
              let type = ControlMessage(rawValue: typeRaw) else { return }

        switch type {
        case .start:
            if let data = dict["payload"] as? Data,
               let payload = try? JSONDecoder().decode(StartPayload.self, from: data) {
                handleStart(payload: payload)
            }
        case .stop:
            handleStop()
        }
    }
    
    // ==========================
    //  START
    // ==========================
    private func handleStart(payload: StartPayload) {
        sessionId = payload.sessionId
        phoneWallAtT0 = payload.phoneWallAtT0
        watchUptimeAtStart = ProcessInfo.processInfo.systemUptime
        
        batch.removeAll(keepingCapacity: true)
        isCollecting = true
        
        // --------------------------------------------------------
        // 변경: DeviceMotion → AccelerometerUpdates 로 전환
        // --------------------------------------------------------
        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = interval
            
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let d = data else { return }
                
                // g 단위 raw accel (중력 포함)
                let ax_g = d.acceleration.x
                let ay_g = d.acceleration.y
                let az_g = d.acceleration.z
                
                // m/s² 변환
                let ax = ax_g * 9.80665
                let ay = ay_g * 9.80665
                let az = az_g * 9.80665
                
                // UI 업데이트
                self.accel_x = ax
                self.accel_y = ay
                self.accel_z = az
                
                // attitude 는 DeviceMotion 에서만 얻을 수 있음 → 별도로 요청
                self.updateDeviceMotionAttitude()
                
                // batch 생성
                self.appendSampleRawAccel(ax: ax, ay: ay, az: az)
            }
        }
        
        // --------------------------------------------------------
        // attitude 얻기 위해 DeviceMotion 별도로 시작 (쿼터니언 필요)
        // --------------------------------------------------------
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = interval
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        }
    }
    
    // ====================
    // Attitude 업데이트
    // (DeviceMotion 보조)ㅈ
    // ====================
    private func updateDeviceMotionAttitude() {
        if let dm = motion.deviceMotion {
            let q = dm.attitude.quaternion
            quart_x = q.x
            quart_y = q.y
            quart_z = q.z
            quart_w = q.w
        }
    }
    
    // =======================================
    // RAW accel + attitude → IMUSample 구성
    // =======================================
    private func appendSampleRawAccel(ax: Double, ay: Double, az: Double) {
        guard isCollecting else { return }
        
        let nowUp = ProcessInfo.processInfo.systemUptime
        let unixTs = phoneWallAtT0 + (nowUp - watchUptimeAtStart)
        
        let wristLoc = WKInterfaceDevice.current().wristLocation
//        let watchDeviceId = (wristLoc == .left) ? 1 : 4
        let watchDeviceId = (wristLoc == .left) ? 0 : 1
        
        // attitude 있음 → 사용
        var qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0
        var roll = 0.0, pitch = 0.0, yaw = 0.0
        
        if let dm = motion.deviceMotion {
            let att = dm.attitude
            let q = att.quaternion
            qx = q.x; qy = q.y; qz = q.z; qw = q.w
            roll = att.roll; pitch = att.pitch; yaw = att.yaw
        }
        
        let sample = IMUSample(
            device_id: watchDeviceId,
            unix_timestamp: unixTs,
            sensor_timestamp: nowUp,
            accel_x: ax, accel_y: ay, accel_z: az,
            quart_x: qx, quart_y: qy, quart_z: qz, quart_w: qw,
            roll: roll, pitch: pitch, yaw: yaw
        )
        
        batch.append(sample)
        if batch.count >= batchSize { flush(isFinal: false) }
    }
    
    // ==========================
    // STOP
    // ==========================
    private func handleStop() {
        guard isCollecting else { return }
        
        isCollecting = false
        
        // 모든 센서 중지
        motion.stopAccelerometerUpdates()
        motion.stopDeviceMotionUpdates()
        motion.stopGyroUpdates()
        
        flush(isFinal: true)
    }
    
    // ==========================
    //  Batching 전송
    // ==========================
    private func flush(isFinal: Bool) {
        guard !batch.isEmpty else { return }
        sendBatchToPhone(sessionId: sessionId, samples: batch, isFinal: isFinal)
        batch.removeAll(keepingCapacity: true)
    }
    
    private func sendBatchToPhone(sessionId: String, samples: [IMUSample], isFinal: Bool) {
        let batch = IMUBatch(sessionId: sessionId, samples: samples, isFinal: isFinal)
        
        do {
            let encoder = JSONEncoder()
            encoder.nonConformingFloatEncodingStrategy = .convertToString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
            let data = try encoder.encode(batch)
            
            let s = WCSession.default
            if s.isReachable {
                s.sendMessageData(data, replyHandler: nil) { error in
                    print("[Watch] sendMessageData error:", error)
                }
            } else {
                s.transferUserInfo(["imuBatch": data])
            }
        } catch {
            print("[Watch] encode IMUBatch error:", error)
        }
    }
}

extension WatchIMUManager: WCSessionDelegate {
    
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            WatchIMUManager.shared.handleInbound(dict: message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any]) {
        Task { @MainActor in
            WatchIMUManager.shared.handleInbound(dict: userInfo)
        }
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            print("[WATCH] WC activated:", activationState.rawValue, "err:", String(describing: error))
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            print("[WATCH] reachabilityDidChange reachable=\(session.isReachable)")
        }
    }
}
