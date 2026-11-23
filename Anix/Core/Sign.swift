import Foundation

/// Порт server/sign.js из репозитория anix: заголовки, которые бекенд ожидает от мобильного клиента.
enum Sign {
    static let versionName = "10.0"
    static let versionCode = 26090418
    static let packageName = "com.swiftsoft.anixartd"
    static let signatureMD5 = "9aa5c7af74e8cd70c86f7f9587bde23d"

    private static let alnum: [Character] = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")

    private static func randomString(_ n: Int) -> String {
        String((0..<n).map { _ in alnum.randomElement()! })
    }

    private static func range(_ a: Int, _ b: Int) -> [Int] { Array(a...b) }

    private static func pool(_ parts: [Int]...) -> [Int] { parts.flatMap { $0 } }

    private static func pick(_ n: Int, _ codes: [Int]) -> String {
        var s = String.UnicodeScalarView()
        for _ in 0..<n { s.append(Unicode.Scalar(UInt8(codes.randomElement()!))) }
        return String(s)
    }

    private static func reverse(_ s: String) -> String { String(s.reversed()) }

    private static func digitShift(_ k: Int, _ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            if u.value >= 48 && u.value <= 57 {
                var c = Int(u.value) - k
                if c < 48 { c += 10 }
                out.append(Unicode.Scalar(UInt8(truncatingIfNeeded: c)))
            } else {
                out.append(u)
            }
        }
        return String(out)
    }

    private static func caesar(_ k: Int, _ s: String) -> String {
        let m = k % 26
        if m == 0 { return s }
        var out = String.UnicodeScalarView()
        for u in s.unicodeScalars {
            var c = Int(u.value)
            if c >= 65 && c < 91 {
                c += m
                if c > 90 { c -= 26 }
            } else if c >= 97 && c < 123 {
                c += m
                if c > 122 { c -= 26 }
            }
            out.append(Unicode.Scalar(UInt8(truncatingIfNeeded: c)))
        }
        return String(out)
    }

    private static func digitCount(_ s: String) -> Int {
        s.unicodeScalars.filter { $0.value >= 48 && $0.value <= 57 }.count
    }

    private static func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString() }

    /// Значение заголовка `Sign`.
    static func sign(sdkInt: Int = 34) -> String {
        let a = randomString(4)
        let b = randomString(8)
        let k = Int.random(in: 1...9)

        let p1 = pick(6, pool(range(65, 70), range(117, 122), range(48, 50), [43, 33, 38, 60, 41]))
        let nowSec = Int(Date().timeIntervalSince1970)
        let str4 = "1" + reverse(String(nowSec))
        let vc = String(versionCode)
        let ts = String((Int(str4) ?? 0) + (Int(vc.suffix(4)) ?? 0))

        let mixCodes = pool(range(78, 90), range(97, 109), range(53, 57), [43, 33, 38, 60, 41])
        var mixed = ""
        for d in ts { mixed += String(d) + pick(1, mixCodes) }

        let p2 = pick(7, pool(range(71, 76), range(111, 116), range(51, 52), [63, 94, 40, 46, 47]))
        let p3 = pick(4, pool(range(77, 82), range(105, 110), range(53, 54), [36, 92, 37, 125, 64]))
        let n1 = [99, 74, 49].randomElement()! - (Int(vc.suffix(2)) ?? 0)
        let p4 = pick(7, pool(range(83, 90), range(97, 104), range(55, 57), [43, 93, 62, 123, 63]))
        let sdkLast = Int(String(sdkInt).suffix(1)) ?? 0
        let r = Int.random(in: 10...27)

        let str5 = p1 + mixed + p2 + p3 + String(n1) + p4 + String(sdkLast) + String(r)
        let rs = String(r)
        let first = Int(String(rs.first!)) ?? 0
        let last = Int(String(rs.last!)) ?? 0
        let i5 = first + last

        let str: String
        if first == 1 {
            str = b64(caesar(last, digitShift(i5 - 1, str5)))
                + String(last)
                + pick(2, pool(range(49, 53), [43, 37, 60, 38, 63]))
                + pick(1, [38, 123, 93, 35, 64])
        } else {
            str = caesar(last, digitShift(i5, b64(str5)))
                + String(last)
                + pick(2, pool(range(54, 57), [33, 94, 62, 126, 47]))
                + pick(1, [37, 125, 91, 36, 94])
        }

        let sigPart = caesar(digitCount(a) + 1, reverse(signatureMD5))
        let pkgPart = caesar(digitCount(b) + 2, packageName)
        return digitShift(k, b64(a + str + sigPart + pkgPart + b)) + String(k) + randomString(7)
    }

    /// Заголовок `X-Codec-Profile` (codecProfile приходит из config/toggles).
    static func codecProfileHeader(_ profile: String?) -> String {
        let i = 128
        let t = Int(Date().timeIntervalSince1970 / 60) & 63
        let x = i ^ t
        let base = "\((x >> 3) + 2).\(x & 7).\((t * 7 + i * 13 + 90) & 255)"
        if let profile, !profile.isEmpty { return base + "." + profile }
        return base
    }

    static var userAgent: String {
        "AnixartApp/\(versionName)-\(versionCode) (Android 14; SDK 34; arm64-v8a; Xiaomi 23049PCD8G; ru)"
    }
}
