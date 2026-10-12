// Kazumi macOS native port. GPL-3.0-or-later. See LICENSE.

/// Shared constants for the native port. The rule schema level matches the
/// Flutter client's `ApiEndpoints.apiLevel`.
public enum KazumiCore {
    public static let version = "0.1.0"
    public static let ruleAPILevel = 8
    public static let projectURL = "https://github.com/Predidit/Kazumi"
    public static let bangumiAPI = "https://api.bgm.tv"
    public static let bangumiNextAPI = "https://next.bgm.tv"
    public static let dandanAPI = "https://api.dandanplay.net"

    public static let bangumiUserAgent =
        "Predidit/Kazumi/\(version) (macOS) (\(projectURL))"

    public static let defaultBrowserUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Safari/605.1.15"

    /// Tags shown on the Flutter popular page (`defaultAnimeTags`).
    public static let defaultAnimeTags = [
        "日常", "原创", "校园", "搞笑", "奇幻", "百合", "恋爱",
        "悬疑", "热血", "后宫", "机战", "轻改", "偶像", "治愈", "异世界",
    ]

    public static let accentPalette: [(id: String, name: String, hex: UInt32)] = [
        ("green", "默认", 0x4CAF50),
        ("teal", "青色", 0x009688),
        ("blue", "蓝色", 0x2196F3),
        ("indigo", "靛蓝色", 0x3F51B5),
        ("violet", "紫罗兰色", 0x6750A4),
        ("pink", "粉红色", 0xE91E63),
        ("yellow", "黄色", 0xFBC02D),
        ("orange", "橙色", 0xFF9800),
        ("deepOrange", "深橙色", 0xFF5722),
    ]
}

public enum KazumiError: Error, Equatable, CustomStringConvertible {
    case message(String)
    case captchaRequired(plugin: String)
    case noResult(plugin: String)
    case http(status: Int, url: String)

    public var description: String {
        switch self {
        case .message(let text):
            return text
        case .captchaRequired(let plugin):
            return "\(plugin) 需要验证码。macOS 版尚未内置 WebView 验证。"
        case .noResult(let plugin):
            return "\(plugin) 没有搜索结果"
        case .http(let status, let url):
            return "HTTP \(status) \(url)"
        }
    }
}
