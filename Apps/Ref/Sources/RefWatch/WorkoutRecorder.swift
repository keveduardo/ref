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
    /// The previous match's workout, still saving — the next kick-off waits
    /// for it (bounded), so two sessions are never live at once.
    private var finishing: Task<HKWorkout?, Never>?
    /// Resumed when an ending session reports `.stopped`.
    private var stopWaiters: [ObjectIdentifier: ResumeOnce<Void>] = [:]

    private(set) var heartRate: Double?
    /// Whether the session is running — and with it, the app held on screen:
    /// watchOS brings a running workout's app back on every wrist raise
    /// (Kevin, 2026-11-06: "it's important that when a game is being timed
    /// that it's the main app on the screen"). False before kick-off and
    /// whenever the session failed, which used to happen silently.
    private(set) var isRunning = false
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

    /// Kick-off. The session runs for the whole match. When the previous
    /// match's workout is still saving (back-to-back games), it waits for
    /// that first — at most the 35 s `finish` allows — and starts from the
    /// real kick-off time.
    func start(at date: Date) {
        starts += 1
        guard let pending = finishing else { begin(at: date); return }
        let mine = starts
        Task {
            _ = await pending.value
            // A kick-off taken back while it waited begins nothing.
            guard self.starts == mine else { return }
            begin(at: date)
        }
    }

    /// Bumped by every start and discard, so a delayed start can tell it was
    /// taken back.
    private var starts = 0

    /// A kick-off taken back (2026-11-14: a game started by mistake on the
    /// afternoon of the match). The session ends and nothing goes to Health.
    func discard() {
        starts += 1
        guard let current = session, let currentBuilder = builder else { return }
        session = nil
        builder = nil
        heartRate = nil
        activeCalories = nil
        isRunning = false
        current.end()
        currentBuilder.discardWorkout()
    }

    private func begin(at date: Date) {
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
        isRunning = recovered.state == .running
        let builder = recovered.associatedWorkoutBuilder()
        builder.delegate = self
        self.builder = builder
    }

    /// Full time: end the collection, save the workout, and freeze what it
    /// cost into a `MatchMetrics` — heart rate, energy, steps and HealthKit's
    /// walking/running distance. The session falls back to the GPS sum when
    /// HealthKit has no distance.
    func finish(route: [RoutePoint] = []) async -> MatchMetrics? {
        guard let current = self.session, let currentBuilder = self.builder else { return nil }
        // No longer this recorder's current workout: callbacks from it are
        // ignored from here on, and the next kick-off may begin — after
        // `finishing`. The locals keep both alive until the save answers.
        self.session = nil
        self.builder = nil
        heartRate = nil
        activeCalories = nil
        isRunning = false
        let end = Date()
        // ! Not Sendable; only ever touched on this actor, inside the task.
        nonisolated(unsafe) let session = current
        nonisolated(unsafe) let builder = currentBuilder

        let work = Task { @MainActor () -> HKWorkout? in
            // Apple's documented order: stop, wait for `.stopped`, end the
            // collection, finish the workout, and only then end the session.
            // The session keeps the app running in the background until it
            // is ended — so a wrist dropped at full time cannot pause the
            // save, and the timeouts below run in real time.
            let stopped = ResumeOnce<Void>()
            self.stopWaiters[ObjectIdentifier(session)] = stopped
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                stopped.set(continuation)
                session.stopActivity(with: end)
                Task {
                    try? await Task.sleep(for: .seconds(5))
                    stopped.resume(())
                }
            }
            self.stopWaiters[ObjectIdentifier(session)] = nil

            // ! `nonisolated(unsafe)` because the SDK's completion handlers
            // are `@Sendable` and the builder is not. It is used from this
            // actor only, to finish a workout that has already been stopped.
            nonisolated(unsafe) let finisher = builder
            // Never more than 30 s: a save that does not answer costs the
            // report its heart rate, never the match.
            let once = ResumeOnce<HKWorkout?>()
            let finished: HKWorkout? = await withCheckedContinuation { continuation in
                once.set(continuation)
                finisher.endCollection(withEnd: end) { _, _ in
                    finisher.finishWorkout { workout, _ in
                        once.resume(workout)
                    }
                }
                Task {
                    try? await Task.sleep(for: .seconds(30))
                    once.resume(nil)
                }
            }
            session.end()
            return finished
        }
        finishing = work
        let finished = await work.value
        if finishing == work { finishing = nil }

        guard let workout = finished else { return nil }
        // The map in Fitness: saved on its own, never waited for — a route
        // save that does not answer costs the map, not the report.
        nonisolated(unsafe) let saved = workout
        Task { await self.saveRoute(route, to: saved) }
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
                                    date: Date) {
        let running = toState == .running, stopped = toState == .stopped
        let id = ObjectIdentifier(workoutSession)
        Task { @MainActor in
            if stopped { self.stopWaiters[id]?.resume(()) }
            // Only the current session speaks for `isRunning`: a late word
            // from the last match's must not show "Workout off" in this one.
            guard self.session.map { ObjectIdentifier($0) } == id else { return }
            self.isRunning = running
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didFailWithError error: any Error) {
        let id = ObjectIdentifier(workoutSession)
        Task { @MainActor in
            self.stopWaiters[id]?.resume(())
            guard self.session.map { ObjectIdentifier($0) } == id else { return }
            self.isRunning = false
        }
    }
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
        let id = ObjectIdentifier(workoutBuilder)
        Task { @MainActor in
            // The last match's builder, still collecting as it saves, must
            // not put its heart rate on this match's screen.
            guard self.builder.map { ObjectIdentifier($0) } == id else { return }
            if let heartRate { self.heartRate = heartRate }
            if let calories { self.activeCalories = calories }
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

/// A continuation resumed by whichever comes first — the SDK's answer or a
/// timeout — and only once.
final class ResumeOnce<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var done = false

    func set(_ continuation: CheckedContinuation<T, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func resume(_ value: sending T) {
        let pending: CheckedContinuation<T, Never>? = lock.withLock {
            guard !done else { return nil }
            done = true
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
