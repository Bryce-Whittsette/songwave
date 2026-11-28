import CoreAudio
import Foundation

// OS boundaries only. Production permission-request and async-handoff code run
// without requesting access, opening audio devices or producing physical output.
enum AccessEdge {
    static let lock = NSLock()
    private static var barrier: DispatchSemaphore?
    private static var metadataBarrier: DispatchSemaphore?
    private static var metadataStarted = false, metadataFinished = false
    private static var calls = 0, finished = 0, alive = 0
    private static var muted = false, fail = false
    private static var excluded: [AudioObjectID] = []
    static func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
    static var counts: (calls: Int, finished: Int, alive: Int) { locked { (calls, finished, alive) } }
    static var requestedMute: Bool { locked { muted } }
    static var excludedProcesses: [AudioObjectID] { locked { excluded } }
    static var metadataState: (started: Bool, finished: Bool) { locked { (metadataStarted, metadataFinished) } }
    static func reset(blocked: Bool = false, failure: Bool = false, blockedMetadata: Bool = false) {
        locked {
            check(alive == 0 && calls == finished)
            calls = 0; finished = 0; muted = false; excluded = []; fail = failure
            barrier = blocked ? DispatchSemaphore(value: 0) : nil
            metadataBarrier = blockedMetadata ? DispatchSemaphore(value: 0) : nil
            metadataStarted = false; metadataFinished = false
        }
    }
    static func processes() -> [AudioObjectID] {
        let wait = locked { metadataStarted = true; return metadataBarrier }
        wait?.wait()
        locked { metadataFinished = true }
        return [101, 202]
    }
    static func releaseMetadata() { let prior = locked { let prior = metadataBarrier; metadataBarrier = nil; return prior }; prior?.signal() }
    static func begin(_ description: CATapDescription, mute: Bool) throws {
        let wait = locked { calls += 1; muted = muted || mute; excluded = description.processes; return barrier }
        wait?.wait()
        let fails = locked { finished += 1; if !fail { alive += 1 }; return fail }
        if fails { throw InjectedFailure() }
    }
    static func release() {
        let prior = locked { let prior = barrier; barrier = nil; return prior }
        for _ in 0..<8 { prior?.signal() }
    }
    static func close() { locked { alive -= 1 } }
}
struct InjectedFailure: Error {}
final class AudioTap {
    private var opened = false
    init(description: CATapDescription, mute: Bool) throws {
        try AccessEdge.begin(description, mute: mute); opened = true
    }
    deinit { if opened { AccessEdge.close() } }
}
enum AudioHardware {
    static func processList() -> [AudioObjectID] { AccessEdge.processes() }
    static func read<T>(_ process: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T) -> OSStatus {
        guard selector == kAudioProcessPropertyPID else { return -1 }
        value = (process == 101 ? getpid() : getpid() + 1) as! T
        return noErr
    }
}
func check(_ condition: @autoclosure () -> Bool, _ message: String = "", line: UInt = #line) {
    if !condition() { fputs("Capture access assertion failed at line \(line): \(message)\n", stderr); exit(1) }
}

@main struct CaptureAccessRegression {
    @MainActor static func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
        check(condition(), "Capture worker or cancellation failed to settle: \(AccessEdge.counts)")
    }
    @MainActor static func drained() async throws {
        try await wait { let c = AccessEdge.counts; return c.calls == c.finished && c.alive == 0 }
        check(!AccessEdge.requestedMute, "An access check muted another app")
    }
    @MainActor static func main() async throws {
        AccessEdge.reset()
        try await PlaybackAccess.requestAudio(timeout: .seconds(2))
        try await drained()
        check(AccessEdge.excludedProcesses == [101], "The global output check must exclude its own process")

        AccessEdge.reset(failure: true)
        do { try await PlaybackAccess.requestAudio(); check(false, "SDK failure was swallowed") }
        catch { check(error is InjectedFailure, "A capture error must not be reclassified as permission denial") }
        try await drained()

        let pending = CaptureRequest(result: nil)
        do { _ = try await pending.wait(timeout: .milliseconds(30)); check(false, "Pending wait did not time out") }
        catch { check(error as? CaptureRequest.Failure == .timedOut) }
        check(pending.takeResult() == nil)

        let cancelled = CaptureRequest(result: nil)
        cancelled.cancel()
        do { _ = try await cancelled.wait(timeout: .seconds(2)); check(false, "Cancelled handoff was accepted") }
        catch { check(error is CancellationError) }

        AccessEdge.reset(blocked: true)
        var completed = false
        let cancellation = Task { () -> Error? in
            defer { completed = true }
            do { try await PlaybackAccess.requestAudio(); return nil } catch { return error }
        }
        try await wait { AccessEdge.counts.calls == 1 }
        cancellation.cancel()
        try await wait { completed }
        let cancelledResult = await cancellation.value
        check(cancelledResult is CancellationError)
        check(AccessEdge.counts.finished == 0, "Cancellation should not wait for the blocked SDK call")
        AccessEdge.release(); try await drained()

        AccessEdge.reset(blocked: true)
        let timeout = Task { () -> Error? in
            do { try await PlaybackAccess.requestAudio(timeout: .seconds(1)); return nil } catch { return error }
        }
        try await wait { AccessEdge.counts.calls == 1 }
        let timeoutResult = await timeout.value
        check(timeoutResult as? CaptureRequest.Failure == .timedOut)
        check(AccessEdge.counts.finished == 0)
        AccessEdge.release(); try await drained()

        AccessEdge.reset(blocked: true)
        let occupied = (0..<4).map { _ in Task { () -> Error? in
            do { try await PlaybackAccess.requestAudio(); return nil } catch { return error }
        } }
        try await wait { AccessEdge.counts.calls == 4 }
        for _ in 0..<8 {
            do { try await PlaybackAccess.requestAudio(); check(false, "Access checks exceeded shared startup admission") }
            catch { check(error as? CaptureRequest.Failure == .busy) }
        }
        occupied.forEach { $0.cancel() }
        for task in occupied { let result = await task.value; check(result is CancellationError) }
        check(AccessEdge.counts.calls == 4 && AccessEdge.counts.finished == 0)
        AccessEdge.release(); try await drained()
        AccessEdge.reset(blockedMetadata: true)
        let metadata = Task { () -> Error? in
            do { try await PlaybackAccess.requestAudio(timeout: .seconds(1)); return nil } catch { return error }
        }
        try await wait { AccessEdge.metadataState.started }
        let metadataResult = await metadata.value
        check(metadataResult as? CaptureRequest.Failure == .timedOut && !AccessEdge.metadataState.finished)
        AccessEdge.releaseMetadata()
        try await wait { AccessEdge.metadataState.finished }
        try await Task.sleep(for: .milliseconds(20))
        check(AccessEdge.counts.calls == 0, "Cancelled metadata preparation started another HAL operation")
        print("Real access checks propagate SDK failures, exclude self, never mute, time out and cancel without waiting on blocked HAL, discard late results, and share the four-worker admission limit.")
        print("A blocked process-list read is inside the same deadline/admission bound; its cancelled late completion cannot start a tap.")
    }
}
