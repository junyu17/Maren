import Foundation

/// Central in-memory broadcaster for local data mutations.
/// Observers receive typed events with a monotonically increasing revision
/// so repeated same-kind events are always distinguishable.
@MainActor
final class LocalDataChangeCenter: ObservableObject {
    static let shared = LocalDataChangeCenter()

    enum ChangeKind: Equatable {
        case storeReset
        case backupImported
        case healthImported
        case quickLogApplied
        case dailyLogChanged
        case dailyLogDeleted
        case customTrackerChanged
        case periodDayDeleted
        case customTrackerDeleted
        case medicationChanged
        case medicationDeleted
        case medicationIntakeChanged
        case medicationIntakeDeleted
    }

    struct Event: Equatable, Identifiable {
        let id = UUID()
        let kind: ChangeKind
        let affectedDayKeys: Set<Int>
        let removedCustomTrackerKeys: Set<String>
        let revision: UInt64
    }

    @Published private(set) var lastEvent: Event?

    private var revisionCounter: UInt64 = 0

    func post(
        kind: ChangeKind,
        affectedDayKeys: Set<Int> = [],
        removedCustomTrackerKeys: Set<String> = []
    ) {
        revisionCounter += 1
        let event = Event(
            kind: kind,
            affectedDayKeys: affectedDayKeys,
            removedCustomTrackerKeys: removedCustomTrackerKeys,
            revision: revisionCounter
        )
        lastEvent = event
    }

    /// Reset the internal counter (for testing only).
    func _resetRevisionCounter() {
        revisionCounter = 0
        lastEvent = nil
    }

    /// Remove deleted custom tracker keys even when a view was not mounted
    /// when the in-memory event was posted.  Built-in symptom keys do not use
    /// the `c:` namespace and are therefore preserved.
    static func sanitizeCustomTrackerKeys(
        _ symptoms: Set<String>,
        availableKeys: Set<String>
    ) -> Set<String> {
        symptoms.filter { !$0.hasPrefix("c:") || availableKeys.contains($0) }
    }
}

enum DailyLogExternalChangePolicy {
    enum Action: Equatable {
        case ignore
        case reset
        case sanitizeTrackers
        case reload
        case conflict
    }

    static func action(
        for event: LocalDataChangeCenter.Event,
        selectedDayKey: Int,
        draftIsDirty: Bool
    ) -> Action {
        switch event.kind {
        case .storeReset:
            return .reset
        case .customTrackerDeleted:
            return .sanitizeTrackers
        default:
            guard event.affectedDayKeys.contains(selectedDayKey) else { return .ignore }
            return draftIsDirty ? .conflict : .reload
        }
    }
}
