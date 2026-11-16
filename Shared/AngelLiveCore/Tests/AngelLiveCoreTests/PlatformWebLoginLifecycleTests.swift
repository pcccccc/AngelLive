import Testing
@testable import AngelLiveCore

@Suite("Web login lifecycle")
struct PlatformWebLoginLifecycleTests {
    @Test("an authenticated account opens its information without starting a login attempt")
    func authenticatedInitialStatus() {
        var lifecycle = PlatformWebLoginLifecycle()
        let generation = lifecycle.beginLoading()
        #expect(!lifecycle.isInitialStatusLoaded)
        #expect(lifecycle.attemptID == nil)

        lifecycle.completeInitialStatus(generation: generation, isAuthenticated: true, startsWithLogin: false)
        #expect(lifecycle.isInitialStatusLoaded)
        #expect(lifecycle.attemptID == nil)
    }

    @Test("an anonymous account or an explicit login request starts an attempt", arguments: [
        (false, false), (true, true)
    ])
    func loginStartsWhenNeeded(isAuthenticated: Bool, startsWithLogin: Bool) throws {
        var lifecycle = PlatformWebLoginLifecycle()
        let generation = lifecycle.beginLoading()
        lifecycle.completeInitialStatus(generation: generation, isAuthenticated: isAuthenticated, startsWithLogin: startsWithLogin)
        let attempt = try #require(lifecycle.attemptID)
        #expect(lifecycle.isInitialStatusLoaded)
        #expect(lifecycle.acceptsCallback(for: attempt))
    }

    @Test("closing and reopening login rejects callbacks from the previous attempt")
    func staleAttemptCannotCommit() {
        var lifecycle = PlatformWebLoginLifecycle()
        let first = lifecycle.beginLoginAttempt()
        #expect(lifecycle.acceptsCallback(for: first))
        lifecycle.stopLoginAttempt()
        #expect(!lifecycle.acceptsCallback(for: first))
        let second = lifecycle.beginLoginAttempt()
        #expect(second != first)
        #expect(!lifecycle.acceptsCallback(for: first))
        #expect(lifecycle.acceptsCallback(for: second))
    }

    @Test("an old status lookup cannot start or replace a newer login attempt")
    func staleInitialStatusCannotOverrideAttempt() {
        var lifecycle = PlatformWebLoginLifecycle()
        let generation = lifecycle.beginLoading()
        let attempt = lifecycle.beginLoginAttempt()
        lifecycle.completeInitialStatus(generation: generation, isAuthenticated: true, startsWithLogin: false)
        #expect(!lifecycle.isCurrentGeneration(generation))
        #expect(lifecycle.attemptID == attempt)
        #expect(lifecycle.acceptsCallback(for: attempt))
    }

    @Test("a status lookup completing after close cannot start a login attempt")
    func staleInitialStatusAfterClose() {
        var lifecycle = PlatformWebLoginLifecycle()
        let generation = lifecycle.beginLoading()
        lifecycle.stopLoginAttempt()
        lifecycle.completeInitialStatus(generation: generation, isAuthenticated: false, startsWithLogin: false)
        #expect(!lifecycle.isCurrentGeneration(generation))
        #expect(lifecycle.attemptID == nil)
    }
}
