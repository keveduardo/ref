import CoreLocation
import Foundation
import HealthKit
import Observation
import RefKit

/// The match's HealthKit workout: heart rate and energy while the referee is
/// on the pitch, behind the distance the location recorder sums.
///
/// Beyond the numbers, the running session is what keeps the app alive with
/// the wrist down (`workout-processing`) — for a referee, that is the point.
/// The shape follows `Apps/Swim/Sources/SwimSession.swift`: `@MainActor`
/// state, `nonisolated` delegate methods, only Sendable values crossing.
@MainActor @Observable final class WorkoutRecorder: NSObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var heartRate: Double?
    private(set) var activeCalories: Double?

    private static var heartRateType: HKQuantityType { HKQuantityType(.heartRate) }
    private static var energyType: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    private static var stepType: HKQuantityType { HKQuantityType(.stepCount) }
    private static var distanceType: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }
    private static var beatUnit: HKUnit { .count().unitDivided(by: .minute()) }

    /// Asked once, before a match — never during one. A refusal costs the
    /// report's numbers, not the match.
    func requestAccess() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        let read: Set<HKObjectType> = [Self.heartRateType, Self.energyType,
                                       Self.distanceType, Self.stepType]
        _ = try? await store.requestAuthorization(toShare: share, read: read)
    }

    /// Kick-off. The session runs for the whole match.
    func start(at date: Date) {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .soccer
        configuration.locationType = .outdoor
        guard let session = try? HKWorkoutSession(healthStore: store, configuration: configuration) else {
            return
        }
        self.session = session
        session.delegate = self
        let builder = session.associatedWorkoutBuilder()
        let source = HKLiveWorkoutDataSource(healthStore: store,
                                             workoutConfiguration: configuration)
        // A soccer workout's default collection is not guaranteed to include
        // these two; asked for by name, they are counted into the workout —
        // and so into the report and the Fitness app.
        source.enableCollection(for: Self.stepType, predicate: nil)
        source.enableCollection(for: Self.distanceType, predicate: nil)
        builder.dataSource = source
        builder.delegate = self
        self.builder = builder
        session.startActivity(with: date)
        builder.beginCollection(withStart: date) { _, _ in }
    }

    /// Relaunched mid-match (a crash, a reboot): take back the workout the
    /// system kept running for us, or — when there is none — start a fresh
    /// one from now. The heart rate before the crash is then lost from the
    /// report; what matters more is that a running session keeps the app
    /// alive with the wrist down, which is what the alarms ride on.
    func recover() async {
        guard session == nil, HKHealthStore.isHealthDataAvailable() else { return }
        // ! `nonisolated(unsafe)` for the same reason as in `finish()`: the
        // completion handler is `@Sendable`, the session it hands back is
        // not, and it is only ever touched on this actor once it arrives.
        nonisolated(unsafe) var recovered: HKWorkoutSession?
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            store.recoverActiveWorkoutSession { session, _ in
                recovered = session
                continuation.resume()
            }
        }
        guard let recovered else {
            start(at: Date())
            return
        }
        session = recovered
        recovered.delegate = self
        let builder = recovered.associatedWorkoutBuilder()
        builder.delegate = self
        self.builder = builder
    }

    /// Full time: end the collection, save the workout, and freeze what it
    /// cost into a `MatchMetrics` — heart rate, energy, steps and HealthKit's
    /// walking/running distance. The session falls back to the GPS sum when
    /// HealthKit has no distance.
    func finish(route: [RoutePoint] = []) async -> MatchMetrics? {
        guard let session, let builder else { return nil }
        session.end()
        let end = Date()

        // ! `nonisolated(unsafe)` because the SDK's completion handlers are
        // `@Sendable` and the builder is not. It is used from this actor only,
        // and only to finish a workout that has already been ended.
        nonisolated(unsafe) let finisher = builder
        let finished: HKWorkout? = await withCheckedContinuation { continuation in
            finisher.endCollection(withEnd: end) { _, _ in
                finisher.finishWorkout { workout, _ in
                    continuation.resume(returning: workout)
                }
            }
        }

        self.session = nil
        self.builder = nil
        heartRate = nil
        activeCalories = nil

        guard let workout = finished else { return nil }
        await saveRoute(route, to: workout)
        let stats = workout.statistics(for: Self.heartRateType)
        return MatchMetrics(
            distanceMeters: workout.statistics(for: Self.distanceType)?
                .sumQuantity()?.doubleValue(for: .meter()),
            averageHeartRate: stats?.averageQuantity()?.doubleValue(for: Self.beatUnit),
            maxHeartRate: stats?.maximumQuantity()?.doubleValue(for: Self.beatUnit),
            activeCalories: workout.statistics(for: Self.energyType)?
                .sumQuantity()?.doubleValue(for: .kilocalorie()),
            steps: workout.statistics(for: Self.stepType)?
                .sumQuantity().map { Int($0.doubleValue(for: .count())) },
            workoutUUID: workout.uuid.uuidString)
    }
}

extension WorkoutRecorder {
    /// The route, attached to the saved workout — Fitness then draws the map
    /// of the match. A failure here costs the map in Fitness, nothing else.
    fileprivate func saveRoute(_ route: [RoutePoint], to workout: HKWorkout) async {
        guard route.count > 1 else { return }
        let locations = route.map {
            CLLocation(coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                       altitude: 0, horizontalAccuracy: $0.accuracy, verticalAccuracy: -1,
                       timestamp: $0.at)
        }
        // ! `nonisolated(unsafe)` as in `finish()`: the builder is not
        // Sendable and the SDK's completion handlers are; it is created,
        // used and dropped inside this one call.
        nonisolated(unsafe) let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
        nonisolated(unsafe) let finishedWorkout = workout
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            routeBuilder.insertRouteData(locations) { inserted, _ in
                guard inserted else { continuation.resume(); return }
                routeBuilder.finishRoute(with: finishedWorkout, metadata: nil) { _, _ in
                    continuation.resume()
                }
            }
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
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRate = workoutBuilder.statistics(for: HKQuantityType(.heartRate))?
            .mostRecentQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute()))
        let calories = workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())
        Task { @MainActor in
            if let heartRate { self.heartRate = heartRate }
            if let calories { self.activeCalories = calories }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
