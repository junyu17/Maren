import Foundation

/// V1.1 今日状态引擎。纯函数:Input DTO → Output。
/// 每条 observation 直接绑定某个输入,不做诊断/hormone/fertility/birth-control 声明。
enum TodayStatusEngine {

    // MARK: - Input DTO

    struct Input {
        let date: Date
        let phase: String?
        let mood: Int?
        let energy: Int?
        let pain: Int?
        let sleepHours: Double?
        let steps: Int?
        let exerciseMinutes: Int?
        let trackerKeys: Set<String>
        let isPerimenopause: Bool
    }

    // MARK: - Output

    struct Output {
        let title: String
        let observations: [String]
        let isDataSparse: Bool
    }

    // MARK: - 核心

    static func evaluate(_ input: Input) -> Output {
        var obs: [String] = []

        addMoodObservation(input, to: &obs)
        addEnergyObservation(input, to: &obs)
        addPainObservation(input, to: &obs)
        addSleepObservation(input, to: &obs)
        addStepsObservation(input, to: &obs)
        addExerciseObservation(input, to: &obs)
        addPerimenopauseObservation(input, to: &obs)
        addTrackerObservation(input, to: &obs)
        addPhaseObservation(input, to: &obs)

        // Phase-only does not make data non-sparse (per requirements)
        let sparse = input.mood == nil && input.energy == nil && input.pain == nil &&
                     input.sleepHours == nil && input.steps == nil &&
                     input.exerciseMinutes == nil && input.trackerKeys.isEmpty

        let title = sparse
            ? String(localized: "今天还没有记录")
            : String(localized: "今日状态")

        return Output(title: title, observations: Array(obs.prefix(3)), isDataSparse: sparse)
    }

    // MARK: - Observations

    private static func addMoodObservation(_ input: Input, to obs: inout [String]) {
        guard let m = input.mood else { return }
        let str = String(localized: "Mood %d/5", defaultValue: "Mood %d/5", comment: "Mood observation")
            .replacingOccurrences(of: "%d", with: "\(m)")
        obs.append(str)
    }

    private static func addEnergyObservation(_ input: Input, to obs: inout [String]) {
        guard let e = input.energy else { return }
        let str = String(localized: "Energy %d/5", defaultValue: "Energy %d/5", comment: "Energy observation")
            .replacingOccurrences(of: "%d", with: "\(e)")
        obs.append(str)
    }

    private static func addPainObservation(_ input: Input, to obs: inout [String]) {
        guard let p = input.pain else { return }
        let str = String(localized: "Pain %d/5", defaultValue: "Pain %d/5", comment: "Pain observation")
            .replacingOccurrences(of: "%d", with: "\(p)")
        obs.append(str)
    }

    private static func addSleepObservation(_ input: Input, to obs: inout [String]) {
        guard let h = input.sleepHours else { return }
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale.current
        let formatted = formatter.string(from: NSNumber(value: h)) ?? "\(h)"
        let str = String(localized: "Sleep %@ hours", defaultValue: "Sleep %@ hours", comment: "Sleep observation")
            .replacingOccurrences(of: "%@", with: formatted)
        obs.append(str)
    }

    private static func addStepsObservation(_ input: Input, to obs: inout [String]) {
        guard let s = input.steps else { return }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        let formatted = formatter.string(from: NSNumber(value: s)) ?? "\(s)"
        let str = String(localized: "%@ steps", defaultValue: "%@ steps", comment: "Steps observation")
            .replacingOccurrences(of: "%@", with: formatted)
        obs.append(str)
    }

    private static func addExerciseObservation(_ input: Input, to obs: inout [String]) {
        guard let ex = input.exerciseMinutes else { return }
        let str = String(localized: "%d minutes exercise", defaultValue: "%d minutes exercise", comment: "Exercise observation")
            .replacingOccurrences(of: "%d", with: "\(ex)")
        obs.append(str)
    }

    private static func addPerimenopauseObservation(_ input: Input, to obs: inout [String]) {
        guard input.isPerimenopause else { return }
        if input.trackerKeys.contains("hotFlashes") || input.trackerKeys.contains("nightSweats") {
            obs.append(String(localized: "You logged hot flashes or night sweats.", comment: "Perimenopause hot flashes/night sweats observation"))
        }
    }

    private static func addTrackerObservation(_ input: Input, to obs: inout [String]) {
        guard !input.trackerKeys.isEmpty, obs.count < 3 else { return }
        // Only filter out hotFlashes/nightSweats for perimenopause users (they get a dedicated observation)
        // For non-perimenopause users, these are treated as regular trackers
        let remainingKeys: Set<String>
        if input.isPerimenopause {
            remainingKeys = input.trackerKeys.filter { !["hotFlashes", "nightSweats"].contains($0) }
        } else {
            remainingKeys = input.trackerKeys
        }
        guard !remainingKeys.isEmpty else { return }
        if remainingKeys.count == 1, let key = remainingKeys.first {
            let str = String(localized: "You logged %@.", defaultValue: "You logged %@.", comment: "Single tracker observation")
                .replacingOccurrences(of: "%@", with: Symptoms.label(for: key))
            obs.append(str)
        } else {
            let str = String(localized: "You logged %d trackers.", defaultValue: "You logged %d trackers.", comment: "Multiple trackers observation")
                .replacingOccurrences(of: "%d", with: "\(remainingKeys.count)")
            obs.append(str)
        }
    }

    private static func addPhaseObservation(_ input: Input, to obs: inout [String]) {
        guard let p = input.phase, p != "unknown" else { return }
        let label: String
        switch p {
        case "menstrual":  label = String(localized: "menstrual", comment: "Menstrual phase")
        case "follicular": label = String(localized: "follicular", comment: "Follicular phase")
        case "ovulatory":  label = String(localized: "ovulatory", comment: "Ovulatory phase")
        case "luteal":     label = String(localized: "luteal", comment: "Luteal phase")
        default:           return
        }
        let str = String(localized: "Estimated to be in %@.", defaultValue: "Estimated to be in %@.", comment: "Phase observation")
            .replacingOccurrences(of: "%@", with: label)
        obs.append(str)
    }
}

// Helper to avoid importing Symptoms in this file if not needed
// Note: Symptoms.label(for:) is used above; ensure Symptoms is accessible
