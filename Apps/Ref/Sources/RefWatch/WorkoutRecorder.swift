import Foundation
import HealthKit
import Observation

/// The match's HealthKit workout: heart rate and energy while the referee is
/// on the pitch, behind the distance the location recorder sums. P0: the
/// session, the builder and both delegate conformances compile; nothing starts
/// one — P4 gives it a caller, and the metrics land in the match record the
/// watch sends home, so the phone needs no Health permission of its own.
///
/// Beyond the numbers, the running session is what keeps the app alive with
/// the wrist down (`workout-processing`), which for a referee is the point.
/// The shape follows `Apps/Swim/Sources/SwimSession.swift`: `@MainActor`
/// state, `nonisolated` delegate methods, only Sendable values crossing.
@MainActor @Observable final class WorkoutRecorder: NSObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var heartRate: Double?
    private(set) var activeCalories: Double?

    /// P4: the session starts at kick-off and is finished at full time; a
    /// match that never kicked off is discarded, not saved (the rule Swim and
    /// Rowing both use).
    func prepare() {
        let config = HKWorkoutConfiguration()
        config.activityType = .soccer
        config.locationType = .outdoor
        session = try? HKWorkoutSession(healthStore: store, configuration: config)
        session?.delegate = self
        if let session {
            builder = session.associatedWorkoutBuilder()
            builder?.dataSource = HKLiveWorkoutDataSource(healthStore: store,
                                                          workoutConfiguration: config)
            builder?.delegate = self
        }
    }
}

extension WorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: any Error) {}
}

extension WorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {}

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
