//import Foundation
//import CoreMotion
//import Combine
//import WatchConnectivity
//
//let device_ids = [
//    "Left_phone": 0,
//    "Left_watch": 1,
//    "Left_headphone": 2,
//    "Right_phone": 3,
//    "Right_watch": 4
//]
//final class PhoneIMU: NSObject, ObservableObject {
//    private let motion = CMMotionManager()
//    private let interval = 1.0 / 100.0 // 100Hz
//    private(set) var sessionId = UUID().uuidString
//
//    // 공통 시간 기준
//    private var phoneWallAtT0: Double = 0.0
//    private var iphoneUptimeAtStart: TimeInterval = 0.0
//
//    // AirPods
//    private let airpods = AirPodsIMU()
//
//    @Published var isCollecting = false
//    
//    @Published var accel_x: Double = 0.0
//    @Published var accel_y: Double = 0.0
//    @Published var accel_z: Double = 0.0
//
//    @Published var quart_x: Double = 0.0
//    @Published var quart_y: Double = 0.0
//    @Published var quart_z: Double = 0.0
//    @Published var quart_w: Double = 0.0
//
//    @Published var isWatchConnected: Bool = false
//    @Published var isAirPodsConnected: Bool = false
//    
//    @Published var iphoneIsLeft: Bool = false   // true = 왼팔, false = 오른팔
//
//    private var currentIphoneDeviceId: Int {
//        iphoneIsLeft ? (device_ids["Left_phone"] ?? 0)
//                     : (device_ids["Right_phone"] ?? 3)
//    }
//    
//    private var bag = Set<AnyCancellable>()
//
//    override init() {
//        super.init()
//
//        // 🔗 Watch 상태 구독
//        PhoneSession.shared.$isPaired
//            .combineLatest(PhoneSession.shared.$isWatchAppInstalled,
//                           PhoneSession.shared.$isReachable)
//            .map { paired, installed, reachable in
//                // “연결됨”의 정의: 페어링 + 설치 (필요 시 && _reachable 로 강화)
//                paired && installed && reachable
//            }
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] connected in
//                self?.isWatchConnected = connected
//            }
//            .store(in: &bag)
//
//        // 🔗 AirPods 연결상태 콜백 → Published 반영
//        airpods.onConnectionChanged = { [weak self] connected in
//            DispatchQueue.main.async { self?.isAirPodsConnected = connected }
//        }
//    }
//
//    func startCollection() {
//        guard !isCollecting else { return }
//        isCollecting = true
//        sessionId = UUID().uuidString
//
//        // (굳이 로컬 매핑 만들 필요 없음 — 파일 상단의 device_ids 사용)
//        // === 공통 시간 기준 ===
//        phoneWallAtT0 = Date().timeIntervalSince1970
//        iphoneUptimeAtStart = ProcessInfo.processInfo.systemUptime
//
//        CSVExporter.shared.beginNewFile(sessionId: sessionId)
//
//        let payload = StartPayload(sessionId: sessionId, phoneWallAtT0: phoneWallAtT0)
//        PhoneSession.shared.sendStart(payload)
//
//        if motion.isDeviceMotionAvailable {
//            motion.deviceMotionUpdateInterval = interval
//            // 현재 선택된 device_id를 캡처해 두면 수집 중 변경되어도 일관성 유지됩니다.
//            let phoneDeviceId = self.currentIphoneDeviceId
//
//            motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical, to: .main) { [weak self] dm, _ in
//                guard let self, let dm else { return }
//                let ua = dm.userAcceleration
//                self.accel_x = ua.x; self.accel_y = ua.y; self.accel_z = ua.z
//
//                let att = dm.attitude
//                self.quart_x = att.quaternion.x
//                self.quart_y = att.quaternion.y
//                self.quart_z = att.quaternion.z
//                self.quart_w = att.quaternion.w
//
//                let nowUp = ProcessInfo.processInfo.systemUptime
//                let unixTs = self.phoneWallAtT0 + (nowUp - self.iphoneUptimeAtStart)
//
//                let sample = IMUSample.fromDeviceMotion(unix_ts: unixTs, dm: dm, device_id: phoneDeviceId)
//                CSVExporter.shared.append(batch: IMUBatch(sessionId: self.sessionId, samples: [sample], isFinal: false))
//            }
//        } else {
//            print("[PhoneIMU] DeviceMotion not available")
//        }
//
//        // AirPods 부분은 그대로 유지
//        airpods.onSample = { [weak self] ap in
//            guard let self else { return }
//            let nowUp  = ProcessInfo.processInfo.systemUptime
//            let unixTs = self.phoneWallAtT0 + (nowUp - self.iphoneUptimeAtStart)
//
//            let s = IMUSample.partial(
//                unix_ts: unixTs,
//                sensor_ts: ap.sensor_timestamp,
//                device_id: device_ids["Left_headphone"] ?? 2,
//                accel_x: ap.accel_x, accel_y: ap.accel_y, accel_z: ap.accel_z
//            )
//            CSVExporter.shared.append(batch: IMUBatch(sessionId: self.sessionId, samples: [s], isFinal: false))
//        }
//        airpods.start(phoneWallAtT0: phoneWallAtT0)
//    }
//    func stopCollection() {
//        guard isCollecting else { return }
//        isCollecting = false
//
//        motion.stopDeviceMotionUpdates()    // DeviceMotion만 쓰는 경우
//        motion.stopAccelerometerUpdates()   // 가속도/자이로도 켰다면 같이 중지
//        motion.stopGyroUpdates()
//        airpods.stop()
//
//        PhoneSession.shared.sendStop(sessionId: sessionId)
//
//        // 화면 값 리셋
//        resetDisplayedValues()
//    }
//    
//    private func resetDisplayedValues() {
//        DispatchQueue.main.async {
//            // iPhone 화면에 보이는 값들 초기화
//            self.accel_x = 0
//            self.accel_y = 0
//            self.accel_z = 0
//            self.quart_x = 0
//            self.quart_y = 0
//            self.quart_z = 0
//            self.quart_w = 0
//        }
//    }
//    
//    // 수동 갱신 버튼용(옵션): WCSession 즉시 조회해 상태 반영
//    func refreshStatuses() {
//        guard WCSession.isSupported() else { return }
//        let s = WCSession.default
//        markWatchConnected(s.isPaired && s.isWatchAppInstalled && s.isReachable)
//        // AirPods는 폴링/콜백으로 자동 반영됨
//    }
//
//    // 수동 세터 (UI에서 사용 가능)
//    func markAirPodsConnected(_ connected: Bool) {
//        DispatchQueue.main.async { self.isAirPodsConnected = connected }
//    }
//    func markWatchConnected(_ connected: Bool) {
//        DispatchQueue.main.async { self.isWatchConnected = connected }
//    }
//}


// PhoneIMU.swift
import Foundation
import CoreMotion
import Combine
import WatchConnectivity

//let device_ids = [
//    "Left_phone": 0,
//    "Left_watch": 1,
//    "Left_headphone": 2,
//    "Right_phone": 3,
//    "Right_watch": 4
//]
let device_ids = [
    "Left_watch": 0,
    "Right_watch": 1,
    "Left_phone": 2,
    "Right_phone": 3,
    "Left_headphone": 4
]


final class PhoneIMU: NSObject, ObservableObject {

    private let motion = CMMotionManager()
    private let interval = 1.0 / 100.0 // 100 Hz

    private(set) var sessionId = UUID().uuidString

    // 공통 시간 기준
    private var phoneWallAtT0: Double = 0.0
    private var iphoneUptimeAtStart: TimeInterval = 0.0

    // AirPods
    private let airpods = AirPodsIMU()

    @Published var isCollecting = false

    // UI 노출용 센서 값
    @Published var accel_x: Double = 0.0
    @Published var accel_y: Double = 0.0
    @Published var accel_z: Double = 0.0

    @Published var quart_x: Double = 0.0
    @Published var quart_y: Double = 0.0
    @Published var quart_z: Double = 0.0
    @Published var quart_w: Double = 0.0

    @Published var isWatchConnected: Bool = false
    @Published var isAirPodsConnected: Bool = false

    @Published var iphoneIsLeft: Bool = false   // true = 왼팔, false = 오른팔

    private var bag = Set<AnyCancellable>()

    private var currentIphoneDeviceId: Int {
        iphoneIsLeft ? (device_ids["Left_phone"] ?? 0)
                      : (device_ids["Right_phone"] ?? 3)
    }

    override init() {
        super.init()

        // Watch 연결 상태 갱신
        PhoneSession.shared.$isPaired
            .combineLatest(
                PhoneSession.shared.$isWatchAppInstalled,
                PhoneSession.shared.$isReachable
            )
            .map { paired, installed, reachable in
                paired && installed && reachable
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ok in self?.isWatchConnected = ok }
            .store(in: &bag)

        // AirPods 연결 상태 반영
        airpods.onConnectionChanged = { [weak self] ok in
            DispatchQueue.main.async { self?.isAirPodsConnected = ok }
        }
    }

    // MARK: - Start Collection
    func startCollection() {
        guard !isCollecting else { return }
        isCollecting = true

        sessionId = UUID().uuidString

        // 공통 시간축 기준 설정
        phoneWallAtT0 = Date().timeIntervalSince1970
        iphoneUptimeAtStart = ProcessInfo.processInfo.systemUptime

        CSVExporter.shared.beginNewFile(sessionId: sessionId)

        let payload = StartPayload(sessionId: sessionId,
                                   phoneWallAtT0: phoneWallAtT0)
        PhoneSession.shared.sendStart(payload)

        let phoneDeviceId = currentIphoneDeviceId

        // ===============================================================
        // 1) Accelerometer RAW (중력 포함) 시작
        // ===============================================================
        if motion.isAccelerometerAvailable {
            motion.accelerometerUpdateInterval = interval
            motion.startAccelerometerUpdates(to: .main) { [weak self] data, _ in
                guard let self, let d = data else { return }

                // g 단위 중력 포함 accel
                let ax_g = d.acceleration.x
                let ay_g = d.acceleration.y
                let az_g = d.acceleration.z

                // m/s² 변환
                let ax = ax_g * 9.80665
                let ay = ay_g * 9.80665
                let az = az_g * 9.80665

                // UI 갱신
                self.accel_x = ax
                self.accel_y = ay
                self.accel_z = az

                // DeviceMotion에서 attitude 가져오기
                var qx = 0.0, qy = 0.0, qz = 0.0, qw = 1.0
                var roll = 0.0, pitch = 0.0, yaw = 0.0

                if let dm = self.motion.deviceMotion {
                    let att = dm.attitude
                    let q = att.quaternion
                    qx = q.x; qy = q.y; qz = q.z; qw = q.w
                    roll = att.roll; pitch = att.pitch; yaw = att.yaw

                    // UI attitude 갱신
                    self.quart_x = qx
                    self.quart_y = qy
                    self.quart_z = qz
                    self.quart_w = qw
                }

                // 시간축 맞추기
                let nowUp = ProcessInfo.processInfo.systemUptime
                let unixTs = self.phoneWallAtT0 + (nowUp - self.iphoneUptimeAtStart)

                // CSV 저장용 IMU Sample 생성
                let sample = IMUSample(
                    device_id: phoneDeviceId,
                    unix_timestamp: unixTs,
                    sensor_timestamp: d.timestamp, // accelerometer timestamp
                    accel_x: ax, accel_y: ay, accel_z: az,
                    quart_x: qx, quart_y: qy, quart_z: qz, quart_w: qw,
                    roll: roll, pitch: pitch, yaw: yaw
                )

                CSVExporter.shared.append(
                    batch: IMUBatch(
                        sessionId: self.sessionId,
                        samples: [sample],
                        isFinal: false
                    )
                )
            }
        } else {
            print("[PhoneIMU] Accelerometer not available")
        }

        // ===============================================================
        // 2) DeviceMotion (attitude만 사용)
        // ===============================================================
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = interval
            motion.startDeviceMotionUpdates(using: .xArbitraryCorrectedZVertical)
        } else {
            print("[PhoneIMU] DeviceMotion not available")
        }

        // ===============================================================
        // 3) AirPods (이미 raw m/s²로 수정됨)
        // ===============================================================
//        airpods.onSample = { [weak self] ap in
//            guard let self else { return }
//
//            let nowUp  = ProcessInfo.processInfo.systemUptime
//            let unixTs = self.phoneWallAtT0 + (nowUp - self.iphoneUptimeAtStart)
//
//            let s = IMUSample.partial(
//                unix_ts: unixTs,
//                sensor_ts: ap.sensor_timestamp,
//                device_id: device_ids["Left_headphone"] ?? 2,
//                accel_x: ap.accel_x,
//                accel_y: ap.accel_y,
//                accel_z: ap.accel_z
//            )
//
//            CSVExporter.shared.append(
//                batch: IMUBatch(
//                    sessionId: self.sessionId,
//                    samples: [s],
//                    isFinal: false
//                )
//            )
//        }
        airpods.onSample = { [weak self] ap in
            guard let self else { return }

            let nowUp  = ProcessInfo.processInfo.systemUptime
            let unixTs = self.phoneWallAtT0 + (nowUp - self.iphoneUptimeAtStart)

            // ap에서 값들을 복사하되, unix_timestamp만 공통 시간축으로 교체
            let full = IMUSample(
                device_id: ap.device_id,                // 또는 device_ids["Left_headphone"] ?? 2
                unix_timestamp: unixTs,                 // ✅ 여기만 바뀐 값
                sensor_timestamp: ap.sensor_timestamp,
                accel_x: ap.accel_x,
                accel_y: ap.accel_y,
                accel_z: ap.accel_z,
                quart_x: ap.quart_x,
                quart_y: ap.quart_y,
                quart_z: ap.quart_z,
                quart_w: ap.quart_w,
                roll: ap.roll,
                pitch: ap.pitch,
                yaw: ap.yaw
            )

            CSVExporter.shared.append(
                batch: IMUBatch(
                    sessionId: self.sessionId,
                    samples: [full],
                    isFinal: false
                )
            )
        }


        airpods.start(phoneWallAtT0: phoneWallAtT0)
    }

    // MARK: - Stop Collection
    func stopCollection() {
        guard isCollecting else { return }
        isCollecting = false

        // 모든 센서 중지
        motion.stopAccelerometerUpdates()
        motion.stopGyroUpdates()
        motion.stopDeviceMotionUpdates()
        airpods.stop()

        PhoneSession.shared.sendStop(sessionId: sessionId)

        resetDisplayedValues()
    }

    private func resetDisplayedValues() {
        DispatchQueue.main.async {
            self.accel_x = 0
            self.accel_y = 0
            self.accel_z = 0
            self.quart_x = 0
            self.quart_y = 0
            self.quart_z = 0
            self.quart_w = 0
        }
    }

    // MARK: - Status Refresh
    func refreshStatuses() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        markWatchConnected(s.isPaired && s.isWatchAppInstalled && s.isReachable)
    }

    func markAirPodsConnected(_ connected: Bool) {
        DispatchQueue.main.async { self.isAirPodsConnected = connected }
    }

    func markWatchConnected(_ connected: Bool) {
        DispatchQueue.main.async { self.isWatchConnected = connected }
    }
}
