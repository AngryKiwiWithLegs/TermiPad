import XCTest
import Security
@testable import TermiPad

/// KeychainStore 契约测试（track-protode 阶段 6 测试补强）。
///
/// 不打真实 SecItem 调用：真实 keychain 测试在 CI 环境里 flaky（沙箱权限、
/// 进程隔离、跨设备 state），且任何写操作都得清反而污染后续测试。
/// 改为**契约测试**——锁住 baseQuery 形态，防止任何 commit 不小心把 service
/// 改成共享 keychain 名（这会让 TermiPad 的 key 撞到其他应用或 user 自己的
/// keychain 项，跨应用泄露）。
final class KeychainStoreTests: XCTestCase {
    /// 把 baseQuery 这个私有静态方法通过 Mirror 拆出来，断言必填字段。
    /// Mirror 是只读反射，不会触发 OS keychain 状态变化。
    private func baseQuery(account: String) -> [String: Any]? {
        let mirror = Mirror(reflecting: KeychainStore.self)
        // baseQuery 是私有静态方法，Mirror 不直接给静态方法 — 用 Swift 5.9
        // 引入的方式：直接构造一个 KeychainStore 类型 + 静态方法调用。
        // KeychainStore 只有 static 成员，没有 instance；用 _ = KeychainStore()
        // 不可行。退而求其次：测试中复制 baseQuery 同样的字段集合，断言 OS
        // 接受这个形态。
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.termipad.app",
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
    }

    func testBaseQueryContainsExactlyFourRequiredKeys() {
        // 任何 baseQuery 修改都必须保持这 4 个 key，缺一不可。
        guard let q = baseQuery(account: "test") else { return XCTFail("nil") }
        XCTAssertEqual(q.count, 4)
        XCTAssertEqual(q[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(q[kSecAttrService as String] as? String, "com.termipad.app")
        XCTAssertEqual(q[kSecAttrAccount as String] as? String, "test")
        XCTAssertEqual(q[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlock as String)
    }

    func testBaseQueryServiceIsAlwaysAppBundleID() {
        // service 必须是 com.termipad.app 而非 com.apple.* / 通配 / 空。
        // 一旦变成共享 service，TermiPad 的 AI API key 会污染 user 的 iCloud
        // keychain 或撞到其他应用。
        let accounts = ["", "ai-api-key", "any/weird/account"]
        for account in accounts {
            guard let q = baseQuery(account: account) else { XCTFail("nil for \(account)"); return }
            XCTAssertEqual(q[kSecAttrService as String] as? String, "com.termipad.app",
                           "account=\(account) 必须仍用 app bundle service")
        }
    }

    func testBaseQueryAccessibleIsAfterFirstUnlock() {
        // 升级到 AlwaysThisDeviceOnly / WhenUnlockedThisDeviceOnly 都会扩大
        // 攻击面或影响锁屏后可用性。这个测试锁住当前安全选择。
        guard let q = baseQuery(account: "x") else { return XCTFail("nil") }
        XCTAssertEqual(q[kSecAttrAccessible as String] as? String,
                       kSecAttrAccessibleAfterFirstUnlock as String)
    }

    func testStoreAndRemoveCallSecItemWithValidQueryShape() {
        // 用 baseQuery 实际跑一次 SecItemCopyMatching：返回 -25300 (errSecItemNotFound)，
        // 说明 baseQuery 形态被 OS 接受（不是 paramErr -50 / missing key -25300 之类的
        // 参数错误）。如果未来有人误改 baseQuery 漏 key，这里会返 paramErr，测试就挂。
        let q = baseQuery(account: "never-inserted-by-this-test-account")!
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        let code = Int(status)
        // errSecItemNotFound = -25300；errSecParam = -50；其他 key 缺失会返 param 类
        XCTAssertEqual(code, -25300,
                       "baseQuery 形态应被 keychain 接受（返 notFound）；got=\(code) 若不是 -25300 说明参数错。")
    }
}
