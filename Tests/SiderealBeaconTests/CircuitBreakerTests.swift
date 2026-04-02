import Foundation
import Testing

@testable import SiderealBeacon

// MARK: - CircuitBreaker Tests

@Suite("CircuitBreaker")
struct CircuitBreakerTests {

    // MARK: - Fresh state

    @Test("Fresh process can restart (closed circuit)")
    func freshProcessCanRestart() async {
        let breaker = CircuitBreaker(maxFailures: 5, windowMinutes: 10)
        let canRestart = await breaker.canRestart(name: "blade")
        #expect(canRestart == true)
    }

    @Test("Fresh process has closed status")
    func freshProcessClosedStatus() async {
        let breaker = CircuitBreaker(maxFailures: 5, windowMinutes: 10)
        let status = await breaker.status(name: "blade")
        guard case .closed = status else {
            Issue.record("Expected closed, got \(status)")
            return
        }
    }

    // MARK: - Backoff after failure

    @Test("After one failure, backoff applies (halfOpen)")
    func singleFailureBackoff() async {
        let breaker = CircuitBreaker(maxFailures: 5, windowMinutes: 10)
        await breaker.recordFailure(name: "blade")

        // Immediately after failure, backoff is 1s, so canRestart should be false
        let canRestart = await breaker.canRestart(name: "blade")
        #expect(canRestart == false)

        let status = await breaker.status(name: "blade")
        guard case .halfOpen(let nextAttemptIn) = status else {
            Issue.record("Expected halfOpen, got \(status)")
            return
        }
        // Should be close to 1 second (with small tolerance for test execution time)
        #expect(nextAttemptIn > 0)
        #expect(nextAttemptIn <= 1.0)
    }

    // MARK: - Circuit opens at max failures

    @Test("Circuit opens after maxFailures within window")
    func circuitOpensAtMaxFailures() async {
        let breaker = CircuitBreaker(maxFailures: 3, windowMinutes: 10)

        await breaker.recordFailure(name: "blade")
        await breaker.recordFailure(name: "blade")
        await breaker.recordFailure(name: "blade")

        let canRestart = await breaker.canRestart(name: "blade")
        #expect(canRestart == false)

        let status = await breaker.status(name: "blade")
        guard case .open(let failures, _) = status else {
            Issue.record("Expected open, got \(status)")
            return
        }
        #expect(failures == 3)
    }

    @Test("Tripped circuit blocks restart even after backoff would expire")
    func trippedCircuitBlocks() async {
        let breaker = CircuitBreaker(maxFailures: 2, windowMinutes: 10)

        await breaker.recordFailure(name: "blade")
        await breaker.recordFailure(name: "blade")

        // Even though backoff would be 2s, the circuit is open/tripped
        let canRestart = await breaker.canRestart(name: "blade")
        #expect(canRestart == false)
    }

    // MARK: - Reset

    @Test("Reset clears failures and closes circuit")
    func resetClearsFailures() async {
        let breaker = CircuitBreaker(maxFailures: 3, windowMinutes: 10)

        await breaker.recordFailure(name: "blade")
        await breaker.recordFailure(name: "blade")
        await breaker.recordFailure(name: "blade")

        // Tripped
        #expect(await breaker.canRestart(name: "blade") == false)

        // Reset
        await breaker.reset(name: "blade")

        #expect(await breaker.canRestart(name: "blade") == true)

        let status = await breaker.status(name: "blade")
        guard case .closed = status else {
            Issue.record("Expected closed after reset, got \(status)")
            return
        }
    }

    @Test("ResetAll clears all processes")
    func resetAllClearsEverything() async {
        let breaker = CircuitBreaker(maxFailures: 2, windowMinutes: 10)

        await breaker.recordFailure(name: "blade")
        await breaker.recordFailure(name: "blade")
        await breaker.recordFailure(name: "lens")
        await breaker.recordFailure(name: "lens")

        await breaker.resetAll()

        #expect(await breaker.canRestart(name: "blade") == true)
        #expect(await breaker.canRestart(name: "lens") == true)
    }

    // MARK: - Backoff intervals increase exponentially

    @Test("Backoff intervals increase with failure count")
    func backoffIncreases() async {
        let breaker = CircuitBreaker(maxFailures: 10, windowMinutes: 10)

        // After 1 failure: 1s backoff
        await breaker.recordFailure(name: "proc")
        let b1 = await breaker.backoffInterval(name: "proc")
        #expect(b1 == 1.0)

        // After 2 failures: 2s backoff
        await breaker.recordFailure(name: "proc")
        let b2 = await breaker.backoffInterval(name: "proc")
        #expect(b2 == 2.0)

        // After 3 failures: 4s backoff
        await breaker.recordFailure(name: "proc")
        let b3 = await breaker.backoffInterval(name: "proc")
        #expect(b3 == 4.0)

        // After 4 failures: 8s backoff
        await breaker.recordFailure(name: "proc")
        let b4 = await breaker.backoffInterval(name: "proc")
        #expect(b4 == 8.0)
    }

    @Test("Backoff caps at 300 seconds")
    func backoffCaps() async {
        let breaker = CircuitBreaker(maxFailures: 20, windowMinutes: 60)

        // Record many failures to exceed schedule length
        for _ in 0 ..< 15 {
            await breaker.recordFailure(name: "proc")
        }

        let backoff = await breaker.backoffInterval(name: "proc")
        #expect(backoff == 300.0)
    }

    // MARK: - Zero backoff for no failures

    @Test("No failures means zero backoff")
    func zeroBackoffNoFailures() async {
        let breaker = CircuitBreaker(maxFailures: 5, windowMinutes: 10)
        let backoff = await breaker.backoffInterval(name: "blade")
        #expect(backoff == 0)
    }

    // MARK: - Independent processes

    @Test("Different process names are tracked independently")
    func independentProcesses() async {
        let breaker = CircuitBreaker(maxFailures: 3, windowMinutes: 10)

        await breaker.recordFailure(name: "blade")
        await breaker.recordFailure(name: "blade")
        await breaker.recordFailure(name: "blade")

        // blade is tripped
        #expect(await breaker.canRestart(name: "blade") == false)
        // lens is fine
        #expect(await breaker.canRestart(name: "lens") == true)
    }
}
