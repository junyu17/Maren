import Foundation

/// 层级 4 · 手表与手机之间的传输协议。
///
/// 为什么不用 App Group:**App Group 只能在同一台设备内共享**,手机和手表是两台设备,
/// 必须走 WatchConnectivity。设计上手表只做两件事:
///   1. 展示手机推过来的快照(一眼看「距下次经期几天」);
///   2. 把「快速记录」动作排队发回手机,由手机写进 SwiftData。
/// 手表**不存自己的库**,因此不存在双向同步冲突。
struct QuickLog: Codable, Equatable {
    /// "period" = 标记今天为经期;"mood" = 记录今天心情。
    var kind: String
    var flowRaw: Int?
    var moodRaw: Int?
    /// 目标日期(yyyymmdd),由手表按自己时区算出「今天」。
    var dayKey: Int
    /// 记录发送时刻。手机端据此判断新旧:
    /// 旧 batch 重放 / 重复送达时,不覆盖手机端更新的值(防止新值被旧值覆盖)。
    var sentAt: Date
    /// 发送端 UTC 偏移秒数(手表所在时区)。手机端校验 dayKey 时参考:
    /// 手表按手表时区算「今天」,若与手机时区不一致,可据此判断差异来源。
    var tzOffsetSeconds: Int

    static func period(flowRaw: Int, dayKey: Int, sentAt: Date = Date(),
                       tzOffsetSeconds: Int = TimeZone.current.secondsFromGMT()) -> QuickLog {
        QuickLog(kind: "period", flowRaw: flowRaw, moodRaw: nil,
                 dayKey: dayKey, sentAt: sentAt, tzOffsetSeconds: tzOffsetSeconds)
    }
    static func mood(moodRaw: Int, dayKey: Int, sentAt: Date = Date(),
                     tzOffsetSeconds: Int = TimeZone.current.secondsFromGMT()) -> QuickLog {
        QuickLog(kind: "mood", flowRaw: nil, moodRaw: moodRaw,
                 dayKey: dayKey, sentAt: sentAt, tzOffsetSeconds: tzOffsetSeconds)
    }
}

enum WatchKeys {
    /// applicationContext 里放快照(总是只保留最新一份)。
    static let snapshot = "vela.snapshot"
    /// transferUserInfo / sendMessage 里放单条快速记录。
    static let quickLog = "vela.quicklog"
    /// applicationContext 里放「最近若干条」的数组(会互相覆盖,靠幂等重放兜底)。
    static let quickLogBatch = "vela.quicklog.batch"
}
