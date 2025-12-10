//import Foundation
//import CoreMotion
//import AVFoundation
//
//final class AirPodsIMU {
//    private let mgr = CMHeadphoneMotionManager()
//    private let queue = OperationQueue()
//    private var phoneWallAtT0: TimeInterval = 0
//    private var uptimeAtStart: TimeInterval = 0
//    private var connectionCheckTimer: Timer?
//
//    var onSample: ((IMUSample) -> Void)?
//    var onConnectionChanged: ((Bool) -> Void)?
//
//    init() {
//        queue.name = "airpods.motion.queue"
//        queue.qualityOfService = .userInitiated
//        // 🔔 라우트 변경 감지
//        NotificationCenter.default.addObserver(self,
//                                               selector: #selector(handleRouteChange),
//                                               name: AVAudioSession.routeChangeNotification,
//                                               object: AVAudioSession.sharedInstance())
//    }
//
//    deinit {
//        NotificationCenter.default.removeObserver(self)
//    }
//
//    func start(phoneWallAtT0: TimeInterval) {
//        self.phoneWallAtT0 = phoneWallAtT0
//        self.uptimeAtStart = ProcessInfo.processInfo.systemUptime
//
//        let session = AVAudioSession.sharedInstance()
//        // 🔧 A2DP/HFP 모두 대비. 필요 시 .defaultToSpeaker 제거 가능
//        try? session.setCategory(.playAndRecord,
//                                 options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers, .defaultToSpeaker])
//        try? session.setActive(true)
//
//        // 🔎 상태 덤프
//        debugDumpStatus(location: "start(begin)")
//
//        if #available(iOS 14.0, *) {
//            let st = CMHeadphoneMotionManager.authorizationStatus()
//            if st == .denied || st == .restricted {
//                print("[HPM] authorization:", st.rawValue, "→ 권한 꺼짐 (설정 > 개인정보 보호 > 모션 & 피트니스)")
//                onConnectionChanged?(false)
//                return
//            }
//        }
//
//        // ⚙️ 업데이트 시작 (이미 Active면 중복 호출 피하기)
//        if !mgr.isDeviceMotionActive {
//            mgr.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
//                guard let self else { return }
//                if let error { print("[HPM] start error:", error.localizedDescription) }
//                guard let m = motion else { return }
//
//                let nowUp = ProcessInfo.processInfo.systemUptime
//                let ts = self.phoneWallAtT0 + (nowUp - self.uptimeAtStart)
//
//                let ua = m.userAcceleration
//                let att = m.attitude
//
//                let s = IMUSample(
//                    device_id: device_ids["Left_headphone"] ?? 2,
//                    unix_timestamp: ts,
//                    sensor_timestamp: m.timestamp,
//                    accel_x: ua.x, accel_y: ua.y, accel_z: ua.z,
//                    quart_x: att.quaternion.x, quart_y: att.quaternion.y,
//                    quart_z: att.quaternion.z, quart_w: att.quaternion.w,
//                    roll: att.roll, pitch: att.pitch, yaw: att.yaw
//                )
//                self.onSample?(s)
//                self.reportConnection(true)
//            }
//        }
//
//        evaluateConnection()
//        startConnectionPolling()
//    }
//
//    func stop() {
//        mgr.stopDeviceMotionUpdates()
//        stopConnectionPolling()
//        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
//        reportConnection(false)
//    }
//
//    // MARK: - Connection
//
//    @objc private func handleRouteChange(_ note: Notification) {
//        // 라우트가 바뀔 때마다 재평가
//        evaluateConnection()
//    }
//
//    private func evaluateConnection() {
//        debugDumpStatus(location: "evaluateConnection")
//
//        let hpmAvailable = mgr.isDeviceMotionAvailable
//        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
//
//        // AirPods/Beats 계열 추정 (필요시 포트명으로 필터 더 추가)
//        let isBT = outputs.contains { out in
//            switch out.portType {
//            case .bluetoothLE, .bluetoothA2DP, .bluetoothHFP: return true
//            default: return false
//            }
//        }
//
//        let active = mgr.isDeviceMotionActive
//        let connected = hpmAvailable && isBT && (active || true) // active 없이도 '연결'로 간주
//
//        reportConnection(connected)
//
//        if connected && !mgr.isDeviceMotionActive {
//            mgr.startDeviceMotionUpdates(to: queue) { [weak self] motion, err in
//                guard let self, let m = motion else {
//                    if let err { print("[HPM] restart error:", err.localizedDescription) }
//                    return
//                }
//                let nowUp = ProcessInfo.processInfo.systemUptime
//                let ts = self.phoneWallAtT0 + (nowUp - self.uptimeAtStart)
//                let ua = m.userAcceleration
//                let att = m.attitude
//                self.onSample?(IMUSample(
//                    device_id: device_ids["Left_headphone"] ?? 2,
//                    unix_timestamp: ts, sensor_timestamp: m.timestamp,
//                    accel_x: ua.x, accel_y: ua.y, accel_z: ua.z,
//                    quart_x: att.quaternion.x, quart_y: att.quaternion.y,
//                    quart_z: att.quaternion.z, quart_w: att.quaternion.w,
//                    roll: att.roll, pitch: att.pitch, yaw: att.yaw
//                ))
//                self.reportConnection(true)
//            }
//        }
//    }
//    
//    private func debugDumpStatus(location: String) {
//        let s = AVAudioSession.sharedInstance()
//        let route = s.currentRoute
//        let outs = route.outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
//        let ins  = route.inputs.map  { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ", ")
//
//        let authStr: String
//        if #available(iOS 14.0, *) {
//            authStr = "\(CMHeadphoneMotionManager.authorizationStatus().rawValue)"
//        } else {
//            authStr = "n/a"
//        }
//        print("""
//        [HPM][\(location)]
//          auth=\(authStr)
//          isDeviceMotionAvailable=\(mgr.isDeviceMotionAvailable)
//          isDeviceMotionActive=\(mgr.isDeviceMotionActive)
//          route.outputs=[\(outs)]
//          route.inputs=[\(ins)]
//        """)
//    }
//
//    private func startConnectionPolling() {
//        stopConnectionPolling()
//        DispatchQueue.main.async {
//            self.connectionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
//                self?.evaluateConnection()
//            }
//        }
//    }
//
//    private func stopConnectionPolling() {
//        connectionCheckTimer?.invalidate()
//        connectionCheckTimer = nil
//    }
//
//    private var lastReported: Bool = false
//    private func reportConnection(_ value: Bool) {
//        if lastReported != value {
//            lastReported = value
//            onConnectionChanged?(value)
//        }
//    }
//}

// AirPodsIMU.swift
import Foundation
import CoreMotion
import AVFoundation

final class AirPodsIMU {
    private let mgr = CMHeadphoneMotionManager()
    private let queue = OperationQueue()
    private var phoneWallAtT0: TimeInterval = 0
    private var uptimeAtStart: TimeInterval = 0
    private var connectionCheckTimer: Timer?

    /// AirPods에서 받은 샘플 콜백
    var onSample: ((IMUSample) -> Void)?
    /// 연결 상태 변경 콜백
    var onConnectionChanged: ((Bool) -> Void)?

    init() {
        queue.name = "airpods.motion.queue"
        queue.qualityOfService = .userInitiated

        // 🔔 오디오 라우트 변경 감지 (연결/해제 등)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public control

    func start(phoneWallAtT0: TimeInterval) {
        self.phoneWallAtT0 = phoneWallAtT0
        self.uptimeAtStart = ProcessInfo.processInfo.systemUptime

        let session = AVAudioSession.sharedInstance()
        // 🔧 A2DP/HFP 모두 대비. 필요 시 .defaultToSpeaker 제거 가능
        try? session.setCategory(
            .playAndRecord,
            options: [.allowBluetooth, .allowBluetoothA2DP, .mixWithOthers, .defaultToSpeaker]
        )
        try? session.setActive(true)

        debugDumpStatus(location: "start(begin)")

        if #available(iOS 14.0, *) {
            let st = CMHeadphoneMotionManager.authorizationStatus()
            if st == .denied || st == .restricted {
                print("[HPM] authorization:", st.rawValue,
                      "→ 권한 꺼짐 (설정 > 개인정보 보호 > 모션 & 피트니스)")
                onConnectionChanged?(false)
                return
            }
        }

        // ⚙️ 업데이트 시작 (이미 Active면 중복 호출 피하기)
        if !mgr.isDeviceMotionActive {
            mgr.startDeviceMotionUpdates(to: queue) { [weak self] motion, error in
                guard let self else { return }
                if let error {
                    print("[HPM] start error:", error.localizedDescription)
                }
                guard let m = motion else { return }

                let nowUp = ProcessInfo.processInfo.systemUptime
                let ts = self.phoneWallAtT0 + (nowUp - self.uptimeAtStart)

                // ===== 핵심: userAcceleration + gravity → 중력 포함 accel =====
                let ua = m.userAcceleration   // g 단위 (gravity 제거된 선형가속도)
                let g  = m.gravity            // g 단위 (기기 좌표계 중력 벡터)

                let ax_g = ua.x + g.x
                let ay_g = ua.y + g.y
                let az_g = ua.z + g.z

                // m/s²로 통일
                let ax = ax_g * 9.80665
                let ay = ay_g * 9.80665
                let az = az_g * 9.80665

                let att = m.attitude
                let q = att.quaternion

                let s = IMUSample(
                    device_id: device_ids["Left_headphone"] ?? 2,
                    unix_timestamp: ts,
                    sensor_timestamp: m.timestamp,
                    accel_x: ax, accel_y: ay, accel_z: az,
                    quart_x: q.x, quart_y: q.y,
                    quart_z: q.z, quart_w: q.w,
                    roll: att.roll, pitch: att.pitch, yaw: att.yaw
                )
                self.onSample?(s)
                self.reportConnection(true)
            }
        }

        evaluateConnection()
        startConnectionPolling()
    }

    func stop() {
        mgr.stopDeviceMotionUpdates()
        stopConnectionPolling()
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: [.notifyOthersOnDeactivation])
        reportConnection(false)
    }

    // MARK: - Connection handling

    @objc private func handleRouteChange(_ note: Notification) {
        // 라우트가 바뀔 때마다 재평가
        evaluateConnection()
    }

    private func evaluateConnection() {
        debugDumpStatus(location: "evaluateConnection")

        let hpmAvailable = mgr.isDeviceMotionAvailable
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs

        // AirPods/Beats 계열 추정 (필요시 포트명으로 필터 더 추가)
        let isBT = outputs.contains { out in
            switch out.portType {
            case .bluetoothLE, .bluetoothA2DP, .bluetoothHFP:
                return true
            default:
                return false
            }
        }

        let active = mgr.isDeviceMotionActive
        let connected = hpmAvailable && isBT && (active || true) // active 없이도 '연결'로 간주

        reportConnection(connected)

        // 연결인데 DeviceMotion이 꺼져있으면 재시작
        if connected && !mgr.isDeviceMotionActive {
            mgr.startDeviceMotionUpdates(to: queue) { [weak self] motion, err in
                guard let self, let m = motion else {
                    if let err {
                        print("[HPM] restart error:", err.localizedDescription)
                    }
                    return
                }
                let nowUp = ProcessInfo.processInfo.systemUptime
                let ts = self.phoneWallAtT0 + (nowUp - self.uptimeAtStart)

                // ⭐ 재시작 시에도 동일하게 raw accel(m/s²) 계산
                let ua = m.userAcceleration
                let g  = m.gravity

                let ax_g = ua.x + g.x
                let ay_g = ua.y + g.y
                let az_g = ua.z + g.z

                let ax = ax_g * 9.80665
                let ay = ay_g * 9.80665
                let az = az_g * 9.80665

                let att = m.attitude
                let q = att.quaternion

                let sample = IMUSample(
                    device_id: device_ids["Left_headphone"] ?? 2,
                    unix_timestamp: ts,
                    sensor_timestamp: m.timestamp,
                    accel_x: ax, accel_y: ay, accel_z: az,
                    quart_x: q.x, quart_y: q.y,
                    quart_z: q.z, quart_w: q.w,
                    roll: att.roll, pitch: att.pitch, yaw: att.yaw
                )
                self.onSample?(sample)
                self.reportConnection(true)
            }
        }
    }
    
    private func debugDumpStatus(location: String) {
        let s = AVAudioSession.sharedInstance()
        let route = s.currentRoute
        let outs = route.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ")
        let ins  = route.inputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ")

        let authStr: String
        if #available(iOS 14.0, *) {
            authStr = "\(CMHeadphoneMotionManager.authorizationStatus().rawValue)"
        } else {
            authStr = "n/a"
        }
        print("""
        [HPM][\(location)]
          auth=\(authStr)
          isDeviceMotionAvailable=\(mgr.isDeviceMotionAvailable)
          isDeviceMotionActive=\(mgr.isDeviceMotionActive)
          route.outputs=[\(outs)]
          route.inputs=[\(ins)]
        """)
    }

    private func startConnectionPolling() {
        stopConnectionPolling()
        DispatchQueue.main.async {
            self.connectionCheckTimer = Timer.scheduledTimer(
                withTimeInterval: 1.0,
                repeats: true
            ) { [weak self] _ in
                self?.evaluateConnection()
            }
        }
    }

    private func stopConnectionPolling() {
        connectionCheckTimer?.invalidate()
        connectionCheckTimer = nil
    }

    private var lastReported: Bool = false
    private func reportConnection(_ value: Bool) {
        if lastReported != value {
            lastReported = value
            onConnectionChanged?(value)
        }
    }
}
