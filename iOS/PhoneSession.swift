import Foundation
import WatchConnectivity
import Combine


// PhoneSession.swift
import WatchConnectivity

final class PhoneSession: NSObject, WCSessionDelegate {
    
    @Published var isPaired: Bool = false
    @Published var isWatchAppInstalled: Bool = false
    @Published var isReachable: Bool = false
    
    static let shared = PhoneSession()
    private override init() { super.init(); activate() }

    private func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // 즉시형 수신
    func session(_ session: WCSession, didReceiveMessageData data: Data) {
        decodeAndAppendIMUBatch(data)
    }

    // 백그라운드 큐잉형 수신
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        if let data = userInfo["imuBatch"] as? Data {
            decodeAndAppendIMUBatch(data)
        }
    }

    private func decodeAndAppendIMUBatch(_ data: Data) {
        do {
            let decoder = JSONDecoder()
            decoder.nonConformingFloatDecodingStrategy = .convertFromString(
                positiveInfinity: "Infinity",
                negativeInfinity: "-Infinity",
                nan: "NaN"
            )
            let batch = try decoder.decode(IMUBatch.self, from: data)
            DispatchQueue.main.async {
                CSVExporter.shared.append(batch: batch)
            }
        } catch {
            print("[Phone] decode IMUBatch error:", error)
        }
    }


    // 이미 쓰고 있는 start/stop 신호도 그대로 유지
    func sendStart(_ payload: StartPayload) {
        do {
            let data = try JSONEncoder().encode(payload)
            let s = WCSession.default
            if s.isReachable {
                print("[PHONE] send START via message (reachable)")
                s.sendMessage(["type": ControlMessage.start.rawValue, "payload": data],
                              replyHandler: nil,
                              errorHandler: { print("[PHONE] send start err:", $0) })
            } else {
                print("[PHONE] queue START via transferUserInfo (not reachable)")
                s.transferUserInfo(["type": ControlMessage.start.rawValue, "payload": data])
            }

            // (선택) 최신 상태 동기화용으로만 컨텍스트 세팅
            try? s.updateApplicationContext(["type": ControlMessage.start.rawValue, "payload": data])
        } catch {
            print("[PHONE] encode start payload err:", error)
        }
    }
    
    func sendStop(sessionId: String) {
        let s = WCSession.default
        let payload: [String: Any] = [
            "type": ControlMessage.stop.rawValue,
            "sessionId": sessionId
        ]

        if s.isReachable {
            print("[PHONE] send STOP via message (reachable)")
            s.sendMessage(payload, replyHandler: nil) { err in
                print("[PHONE] send stop err:", err)
            }
        } else {
            print("[PHONE] queue STOP via transferUserInfo (not reachable)")
            s.transferUserInfo(payload)
        }

        // (옵션) 최신 상태 동기화용 — 없어도 됨
        try? s.updateApplicationContext(payload)
    }
    
    // 필수 델리게이트 (iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        print("[PHONE] WC activated:", activationState.rawValue, "err:", String(describing: error))
        updateState(from: session)
    }
    func sessionWatchStateDidChange(_ session: WCSession) {
        print("[PHONE] watchStateDidChange paired=\(session.isPaired) installed=\(session.isWatchAppInstalled)")
        updateState(from: session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[PHONE] reachabilityDidChange reachable=\(session.isReachable)")
        updateState(from: session)
    }
    
    private func updateState(from session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }
    }
}
