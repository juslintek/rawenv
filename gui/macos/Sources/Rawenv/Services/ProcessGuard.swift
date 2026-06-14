import Foundation

/// Global safety governor for ALL subprocess launches in the app.
///
/// This is a hard safety net: no matter what bug exists in the UI layer (a view
/// that re-renders in a loop, a runaway `.task`, etc.), the app can never spawn
/// an unbounded number of OS processes and crash the machine.
///
/// Two independent protections:
///   1. **Concurrency cap** — at most `maxConcurrent` subprocesses run at once.
///      Additional launches block briefly, then are refused. You physically
///      cannot have thousands of `rawenv`/`lsof`/`ps` processes alive together.
///   2. **Circuit breaker** — if the spawn *rate* exceeds `maxPerWindow` within
///      `windowSeconds`, the breaker trips and refuses all launches for a
///      cooldown. A real runaway loop is stopped within a few dozen spawns
///      instead of escalating into a fork bomb.
///
/// Every `Process` launch in the app MUST go through `ProcessGuard.run` (or
/// guard manually with `acquire()`/`release()`). When a launch is refused the
/// caller falls back to a safe default (empty/nil), so the app degrades to
/// "no live data" rather than taking down the system.
public final class ProcessGuard: @unchecked Sendable {
    public static let shared = ProcessGuard()

    // Tunables. A real runaway loop spawns processes exponentially — thousands
    // per second — so even generous limits catch it within milliseconds. These
    // are set high enough that the full parallel test suite and normal
    // interactive use never trip them.
    private let maxConcurrent = 24
    private let maxPerWindow = 1000
    private let windowSeconds: TimeInterval = 10
    private let cooldownSeconds: TimeInterval = 15
    private let acquireTimeout: TimeInterval = 30

    private let semaphore: DispatchSemaphore
    private let lock = NSLock()
    private var windowStart = Date()
    private var windowCount = 0
    private var trippedUntil: Date?

    public init() {
        semaphore = DispatchSemaphore(value: maxConcurrent)
    }

    /// Try to reserve a subprocess slot. Returns `true` if the caller may launch
    /// a process (and MUST later call `release()`); `false` if the launch is
    /// refused by the circuit breaker or concurrency timeout (caller must NOT
    /// launch and must NOT call `release()`).
    public func acquire() -> Bool {
        lock.lock()
        let now = Date()

        // Circuit breaker in cooldown?
        if let until = trippedUntil {
            if now < until { lock.unlock(); return false }
            // Cooldown elapsed — reset.
            trippedUntil = nil
            windowStart = now
            windowCount = 0
        }

        // Slide the rate window.
        if now.timeIntervalSince(windowStart) > windowSeconds {
            windowStart = now
            windowCount = 0
        }
        windowCount += 1
        if windowCount > maxPerWindow {
            trippedUntil = now.addingTimeInterval(cooldownSeconds)
            lock.unlock()
            NSLog("[rawenv] ProcessGuard circuit breaker TRIPPED — refusing subprocess launches for \(Int(cooldownSeconds))s (runaway spawn rate detected)")
            return false
        }
        lock.unlock()

        // Enforce the concurrency cap. Bounded wait so a stuck child can never
        // deadlock the whole app.
        return semaphore.wait(timeout: .now() + acquireTimeout) == .success
    }

    /// Release a slot reserved by a successful `acquire()`.
    public func release() {
        semaphore.signal()
    }

    /// Convenience wrapper: runs `body` only if a slot is available, always
    /// releasing afterwards. Returns `fallback` if the launch was refused.
    public func run<T>(fallback: T, _ body: () -> T) -> T {
        guard acquire() else { return fallback }
        defer { release() }
        return body()
    }
}
