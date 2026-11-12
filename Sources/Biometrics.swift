import Foundation
import LocalAuthentication

enum Biometrics {

    /// 仅当设备具备安全区时才显示安全支付入口；服务端仍会逐笔验签。
    static var paymentReady: Bool { PaymentDeviceSigning.secureHardwareAvailable }

    static var available: Bool {
        var err: NSError?
        let ok = context().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        return ok
    }

    static var label: String {
        let ctx = context()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else { return "使用面容" }
        switch ctx.biometryType {
        case .touchID: return "使用指纹"
        default: return "使用面容"
        }
    }

    static func authenticate(reason: String) async -> (ok: Bool, message: String) {
        let ctx = context()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            let code = (err as? LAError)?.code
            if code == .biometryNotEnrolled {
                return (false, "这台手机还没录入面容 ID，去「系统设置 → 面容 ID 与密码」里加上就能用")
            }
            if code == .biometryLockout {
                return (false, "面容 ID 被锁住了，先用手机密码解锁一次")
            }
            return (false, "这台手机不支持面容 ID，直接输支付密码吧")
        }
        do {
            let ok = try await evaluate(ctx, reason: reason)
            return (ok, ok ? "" : "面容没认出来，再试一次或直接输支付密码")
        } catch let e as LAError {
            switch e.code {
            case .userCancel, .appCancel, .systemCancel:
                return (false, "")
            case .userFallback:
                return (false, "请输入支付密码")
            case .biometryNotEnrolled:
                return (false, "这台手机还没录入面容 ID，去「系统设置 → 面容 ID 与密码」里加上就能用")
            case .biometryLockout:
                return (false, "面容 ID 被锁住了，先用手机密码解锁一次")
            case .biometryNotAvailable:
                return (false, "面容 ID 暂时不可用，直接输支付密码吧")
            default:
                return (false, "面容没通过，直接输支付密码吧")
            }
        } catch {
            return (false, "面容没通过，直接输支付密码吧")
        }
    }

    private static func evaluate(_ ctx: LAContext, reason: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, err in
                if let err = err {
                    cont.resume(throwing: err)
                } else {
                    cont.resume(returning: ok)
                }
            }
        }
    }

    private static func context() -> LAContext {
        let ctx = LAContext()
        ctx.localizedFallbackTitle = "输入支付密码"
        ctx.localizedCancelTitle = "取消"
        return ctx
    }
}
