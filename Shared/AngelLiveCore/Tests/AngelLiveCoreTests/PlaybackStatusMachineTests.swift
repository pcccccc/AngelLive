import Testing
@testable import AngelLiveCore

@Suite("PlaybackStatusMachine")
struct PlaybackStatusMachineTests {
    @Test("KSPlayer engine states map to accurate display states", arguments: [
        (PlaybackEngineState.preparing, false, PlaybackStatus.loading),
        (.readyToPlay, false, .loading),
        (.readyToPlay, true, .loading),
        (.buffering, false, .buffering),
        (.buffering, true, .buffering),
        (.bufferFinished, true, .playing),
        (.bufferFinished, false, .paused),
        (.paused, false, .paused),
        (.ended, false, .ended),
        (.error, false, .failed(message: nil))
    ])
    func engineStateMapping(
        state: PlaybackEngineState,
        isPlaying: Bool,
        expected: PlaybackStatus
    ) {
        var machine = PlaybackStatusMachine()
        machine.send(.loadRequested)
        machine.send(.engineStateChanged(state, isPlaying: isPlaying))
        #expect(machine.status == expected)
    }

    @Test("readyToPlay never means playing")
    func readyToPlayIsLoading() {
        var machine = PlaybackStatusMachine()
        machine.send(.loadRequested)
        machine.send(.engineStateChanged(.readyToPlay, isPlaying: true))

        #expect(machine.status == .loading)
        #expect(!machine.status.isPlaying)
        #expect(machine.status.isLoading)
    }

    @Test("active reset loads while stopped reset stays idle")
    func initializedRespectsSessionLifecycle() {
        var machine = PlaybackStatusMachine()
        machine.send(.engineStateChanged(.initialized, isPlaying: false))
        #expect(machine.status == .idle)

        machine.send(.loadRequested)
        machine.send(.engineStateChanged(.initialized, isPlaying: false))
        #expect(machine.status == .loading)

        machine.send(.stopped)
        machine.send(.engineStateChanged(.initialized, isPlaying: false))
        #expect(machine.status == .idle)
    }

    @Test("explicit failure keeps its diagnostic message")
    func explicitFailure() {
        var machine = PlaybackStatusMachine()
        machine.send(.loadRequested)
        machine.send(.failed(message: "unsupported stream"))
        #expect(machine.status == .failed(message: "unsupported stream"))
    }
}
