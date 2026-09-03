import Foundation
import Testing
@testable import AngelLiveCore

@Suite("Plugin QR-code login protocol")
struct PlatformLoginChallengeManifestTests {
    @Test("loginChallenge is explicit and independent from loginFlow and auth")
    func explicitCapabilityDeclaration() throws {
        let withoutChallenge = try decodeManifest("""
        {
          "pluginId": "fixture.login",
          "version": "1.0.0",
          "apiVersion": 1,
          "liveTypes": ["fixture"],
          "entry": "index.js",
          "auth": { "required": true },
          "loginFlow": {
            "loginURL": "https://example.invalid/login",
            "cookieDomains": ["example.invalid"],
            "authSignalCookies": ["session"]
          }
        }
        """)

        #expect(withoutChallenge.loginChallenge == nil)

        let withChallenge = try decodeManifest("""
        {
          "pluginId": "fixture.login",
          "version": "1.0.0",
          "apiVersion": 1,
          "liveTypes": ["fixture"],
          "entry": "index.js",
          "loginChallenge": {
            "kind": "qrcode",
            "minLoginChallengeProtocol": 1
          }
        }
        """)

        #expect(withChallenge.loginFlow == nil)
        #expect(withChallenge.loginChallenge?.kind == .qrcode)
        #expect(withChallenge.loginChallenge?.isSupportedByCurrentHost == true)
    }

    @Test("manifest defaults and clamps untrusted scheduling values")
    func defaultsAndClamps() throws {
        let manifest = try decodeManifest("""
        {
          "pluginId": "fixture.login",
          "version": "1.0.0",
          "apiVersion": 1,
          "liveTypes": ["fixture"],
          "entry": "index.js",
          "loginChallenge": {
            "kind": "qrcode",
            "minLoginChallengeProtocol": -4,
            "functions": { "create": " ", "poll": "customPoll" },
            "pollIntervalMs": -1,
            "timeoutSeconds": 999999,
            "maxRefreshes": 500,
            "hint": "  Scan in the app  ",
            "preferOn": ["TVOS", "futureOS"]
          }
        }
        """)
        let challenge = try #require(manifest.loginChallenge)

        #expect(challenge.minLoginChallengeProtocol == 1)
        #expect(challenge.pollIntervalMs == 1_000)
        #expect(challenge.timeoutSeconds == 600)
        #expect(challenge.maxRefreshes == 10)
        #expect(challenge.functions.create == ManifestLoginChallengeFunctions.defaultCreate)
        #expect(challenge.functions.poll == "customPoll")
        #expect(challenge.functions.cancel == ManifestLoginChallengeFunctions.defaultCancel)
        #expect(challenge.functions.submitVerification == ManifestLoginChallengeFunctions.defaultSubmitVerification)
        #expect(challenge.functions.resendVerification == ManifestLoginChallengeFunctions.defaultResendVerification)
        #expect(challenge.hint == "Scan in the app")
        #expect(challenge.prefers(.tvOS))
        #expect(!challenge.prefers(.macOS))
    }

    @Test("unknown challenge kinds survive decoding but are unsupported")
    func unknownKind() throws {
        let manifest = try decodeManifest("""
        {
          "pluginId": "fixture.login",
          "version": "1.0.0",
          "apiVersion": 1,
          "liveTypes": ["fixture"],
          "entry": "index.js",
          "loginChallenge": { "kind": "device_code" }
        }
        """)
        let challenge = try #require(manifest.loginChallenge)

        #expect(challenge.kind == .unsupported("device_code"))
        #expect(!challenge.isSupportedByCurrentHost)
    }

    @Test("challenge functions cannot alias host credential mutators")
    func reservedCredentialFunctionIsUnsupported() throws {
        let manifest = try decodeManifest("""
        {
          "pluginId": "fixture.login",
          "version": "1.0.0",
          "apiVersion": 1,
          "liveTypes": ["fixture"],
          "entry": "index.js",
          "loginChallenge": {
            "kind": "qrcode",
            "functions": { "create": " setCredential " }
          }
        }
        """)
        let challenge = try #require(manifest.loginChallenge)

        #expect(challenge.functions.usesReservedCredentialFunction)
        #expect(!challenge.isSupportedByCurrentHost)
    }

    @Test("UNSUPPORTED is a standardized plugin error")
    func unsupportedStandardError() {
        let error = LiveParsePluginError.fromJSException(
            #"LP_PLUGIN_ERROR:{"code":"UNSUPPORTED","message":"host is too old"}"#
        )
        guard case .standardized(let standard) = error else {
            Issue.record("Expected a standardized error")
            return
        }
        #expect(standard.code == .unsupported)
    }

    private func decodeManifest(_ json: String) throws -> LiveParsePluginManifest {
        try JSONDecoder().decode(LiveParsePluginManifest.self, from: Data(json.utf8))
    }
}

@Suite("Platform login challenge state machine", .serialized)
@MainActor
struct PlatformLoginChallengeServiceTests {
    @Test("confirmed means credential ready when compatibility flag is absent")
    func confirmedWithoutCompatibilityFlagSucceeds() async {
        let driver = ChallengeDriver(
            creates: [.fixture()],
            polls: [.init(state: .confirmed, uid: "poll-user")]
        )
        let service = makeService(driver: driver)

        service.start(entry: .fixture(), platform: .tvOS)
        await service.waitForCurrentOperation()

        #expect(service.state == .succeeded(.init(userId: "status-user", userName: "Fixture User")))
        let snapshot = await driver.snapshot()
        #expect(snapshot.promoteCount == 1)
        #expect(snapshot.loginCount == 1)
        #expect(snapshot.didLoginCount == 1)
        #expect(snapshot.createFunctions == ["createLoginChallenge"])
        #expect(snapshot.pollFunctions == ["pollLoginChallenge"])
        #expect(snapshot.cancelledChallengeIds.isEmpty)
        #expect(snapshot.discardCount == 0)
    }

    @Test("contradictory credentialReady is rejected before promotion")
    func contradictoryCredentialReadinessFails() async {
        let driver = ChallengeDriver(
            creates: [.fixture()],
            polls: [.init(state: .confirmed, credentialReady: false)]
        )
        let service = makeService(driver: driver)

        service.start(entry: .fixture(), platform: .macOS)
        await service.waitForCurrentOperation()

        guard case .failed(let failure) = service.state else {
            Issue.record("Expected protocol failure")
            return
        }
        #expect(failure.kind == .invalidResponse)
        #expect(failure.message.contains("矛盾"))
        let snapshot = await driver.snapshot()
        #expect(snapshot.promoteCount == 0)
        #expect(snapshot.loginCount == 0)
    }

    @Test("waiting and scanned states remain observable between polls")
    func waitingAndScannedStatesAreObservable() async {
        let driver = ChallengeDriver(
            creates: [.fixture()],
            polls: [
                .init(state: .waiting),
                .init(state: .scanned),
                .init(state: .confirmed)
            ],
            suspendedSleeps: [2, 3]
        )
        let service = makeService(driver: driver)

        service.start(entry: .fixture(), platform: .tvOS)
        #expect(await eventually { await driver.hasSuspendedSleep(2) })
        guard case .presenting = service.state else {
            Issue.record("Expected waiting to keep the presenting state")
            return
        }

        await driver.resumeSleep(2)
        #expect(await eventually { await driver.hasSuspendedSleep(3) })
        guard case .scanned = service.state else {
            Issue.record("Expected scanned state")
            return
        }

        await driver.resumeSleep(3)
        await service.waitForCurrentOperation()
        guard case .succeeded = service.state else {
            Issue.record("Expected the final confirmed response to succeed")
            return
        }
    }

    @Test("plugin-provided PNG is shown instead of encoding qrContent")
    func pluginPNGIsPresented() async throws {
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let created = try JSONDecoder().decode(
            LoginChallengeCreateResponse.self,
            from: Data(#"""
            {
              "kind": "qrcode",
              "challengeId": "challenge-png",
              "qrContent": "https://example.invalid/long-qr-url",
              "qrImage": "data:image/png;base64,\#(pngBase64)",
              "pollIntervalMs": 1000
            }
            """#.utf8)
        )
        let driver = ChallengeDriver(
            creates: [created],
            polls: [.init(state: .waiting)],
            suspendedSleeps: [1]
        )
        let service = makeService(driver: driver)

        service.start(entry: .fixture(), platform: .iOS)
        #expect(await eventually { await driver.hasSuspendedSleep(1) })
        guard case .presenting(let presentation) = service.state else {
            Issue.record("Expected presenting state")
            return
        }
        #expect(presentation.qrContent == "https://example.invalid/long-qr-url")
        let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        #expect(presentation.qrImageData?.prefix(pngMagic.count) == pngMagic)

        service.cancel()
        await service.waitForCurrentOperation()
    }

    @Test("plugin failed state stops without promoting credentials")
    func pluginFailedStateStops() async {
        let driver = ChallengeDriver(
            creates: [.fixture()],
            polls: [.init(state: .failed, message: "risk control")]
        )
        let service = makeService(driver: driver)

        service.start(entry: .fixture(), platform: .tvOS)
        await service.waitForCurrentOperation()

        guard case .failed(let failure) = service.state else {
            Issue.record("Expected plugin failure")
            return
        }
        #expect(failure.kind == .plugin)
        #expect(failure.message == "risk control")
        #expect((await driver.snapshot()).promoteCount == 0)
    }

    @Test("verification state requires a v2 manifest declaration")
    func verificationRequiresV2Manifest() async {
        let driver = ChallengeDriver(
            creates: [.fixture()],
            polls: [.init(
                state: .verificationRequired,
                verification: .init(kind: .smsCode, verificationId: "verify-1")
            )]
        )
        let service = makeService(driver: driver)

        service.start(entry: .fixture(challenge: .fixture(minProtocol: 1)), platform: .tvOS)
        await service.waitForCurrentOperation()

        guard case .failed(let failure) = service.state else {
            Issue.record("Expected a protocol version failure")
            return
        }
        #expect(failure.kind == .invalidResponse)
        #expect(failure.message.contains("manifest 未声明 v2"))
        #expect((await driver.snapshot()).verificationSubmitCount == 0)
    }

    @Test("SMS verification pauses polling then resumes the same challenge")
    func smsVerificationResumesPolling() async {
        let verification = LoginChallengeVerificationDescriptor(
            kind: .smsCode,
            verificationId: "verify-1",
            prompt: "请输入短信验证码",
            maskedDestination: "138****0000",
            codeLength: 6,
            canResend: true,
            resendAfterMs: 30_000
        )
        let driver = ChallengeDriver(
            creates: [.fixture()],
            polls: [
                .init(state: .verificationRequired, rawStatus: 2046, verification: verification),
                .init(state: .confirmed)
            ],
            verificationSubmits: [.init(state: .accepted)]
        )
        let service = makeService(driver: driver)

        service.start(entry: .fixture(challenge: .fixture(minProtocol: 2)), platform: .tvOS)
        #expect(await eventually {
            guard case .awaitingVerification = service.state else { return false }
            return true
        })
        guard case .awaitingVerification(let presentation) = service.state else {
            Issue.record("Expected SMS verification input")
            return
        }
        #expect(presentation.maskedDestination == "138****0000")
        #expect(presentation.codeLength == 6)
        #expect(presentation.canResend)

        service.submitVerificationCode("123456")
        await service.waitForCurrentOperation()

        guard case .succeeded = service.state else {
            Issue.record("Expected polling to resume and finish")
            return
        }
        let snapshot = await driver.snapshot()
        #expect(snapshot.verificationSubmitCount == 1)
        #expect(snapshot.verificationSubmitFunctions == ["submitLoginChallengeVerification"])
        #expect(snapshot.promoteCount == 1)
    }

    @Test("a rejected SMS code remains in the verification step")
    func rejectedSMSCodeCanBeRetried() async {
        let verification = LoginChallengeVerificationDescriptor(
            kind: .smsCode,
            verificationId: "verify-1",
            maskedDestination: "138****0000"
        )
        let driver = ChallengeDriver(
            creates: [.fixture()],
            polls: [
                .init(state: .verificationRequired, verification: verification),
                .init(state: .confirmed)
            ],
            verificationSubmits: [
                .init(state: .rejected, message: "验证码错误"),
                .init(state: .accepted)
            ]
        )
        let service = makeService(driver: driver)

        service.start(entry: .fixture(challenge: .fixture(minProtocol: 2)), platform: .iOS)
        #expect(await eventually {
            guard case .awaitingVerification = service.state else { return false }
            return true
        })
        service.submitVerificationCode("111111")
        #expect(await eventually {
            guard case .awaitingVerification(let prompt) = service.state else { return false }
            return prompt.errorMessage == "验证码错误"
        })

        service.submitVerificationCode("222222")
        await service.waitForCurrentOperation()
        guard case .succeeded = service.state else {
            Issue.record("Expected the corrected SMS code to succeed")
            return
        }
        #expect((await driver.snapshot()).verificationSubmitCount == 2)
    }

    @Test("SMS verification can request a new code before submission")
    func smsVerificationCanResend() async {
        let initial = LoginChallengeVerificationDescriptor(
            kind: .smsCode,
            verificationId: "verify-1",
            maskedDestination: "138****0000",
            canResend: true,
            resendAfterMs: 0
        )
        let refreshed = LoginChallengeVerificationDescriptor(
            kind: .smsCode,
            verificationId: "verify-2",
            maskedDestination: "138****0000",
            canResend: true,
            resendAfterMs: 60_000
        )
        let driver = ChallengeDriver(
            creates: [.fixture()],
            polls: [
                .init(state: .verificationRequired, verification: initial),
                .init(state: .confirmed)
            ],
            verificationSubmits: [.init(state: .accepted)],
            verificationResends: [refreshed]
        )
        let service = makeService(driver: driver)

        service.start(entry: .fixture(challenge: .fixture(minProtocol: 2)), platform: .macOS)
        #expect(await eventually {
            guard case .awaitingVerification = service.state else { return false }
            return true
        })
        service.resendVerificationCode()
        #expect(await eventually {
            guard case .awaitingVerification(let prompt) = service.state else { return false }
            return prompt.errorMessage == "验证码已重新发送"
                && prompt.resendAvailableAt != nil
        })

        service.submitVerificationCode("123456")
        await service.waitForCurrentOperation()
        guard case .succeeded = service.state else {
            Issue.record("Expected resent SMS verification to finish")
            return
        }
        let snapshot = await driver.snapshot()
        #expect(snapshot.verificationResendCount == 1)
        #expect(snapshot.verificationResendFunctions == ["resendLoginChallengeVerification"])
    }

    @Test("cancelling while waiting for an SMS code discards the challenge")
    func cancelWhileAwaitingSMSCode() async {
        let verification = LoginChallengeVerificationDescriptor(
            kind: .smsCode,
            verificationId: "verify-1"
        )
        let driver = ChallengeDriver(
            creates: [.fixture()],
            polls: [.init(state: .verificationRequired, verification: verification)]
        )
        let service = makeService(driver: driver)

        service.start(entry: .fixture(challenge: .fixture(minProtocol: 2)), platform: .tvOS)
        #expect(await eventually {
            guard case .awaitingVerification = service.state else { return false }
            return true
        })
        service.cancel()
        await service.waitForCurrentOperation()

        #expect(service.state == .idle)
        let snapshot = await driver.snapshot()
        #expect(snapshot.discardCount == 1)
        #expect(snapshot.cancelledChallengeIds == ["challenge"])
        #expect(snapshot.verificationSubmitCount == 0)
    }

    @Test("oversized QR content is rejected before presentation")
    func oversizedQRContentFails() async {
        let driver = ChallengeDriver(
            creates: [.fixture(qr: String(repeating: "x", count: 2_332))],
            polls: []
        )
        let service = makeService(driver: driver)

        service.start(entry: .fixture(), platform: .tvOS)
        await service.waitForCurrentOperation()

        guard case .failed(let failure) = service.state else {
            Issue.record("Expected oversized QR content to fail")
            return
        }
        #expect(failure.kind == .invalidResponse)
        #expect(failure.message.contains("二维码内容过长"))
        let snapshot = await driver.snapshot()
        #expect(snapshot.pollFunctions.isEmpty)
        #expect(snapshot.promoteCount == 0)
    }

    @Test("unsupported start clears a prior retry request")
    func unsupportedStartClearsRetry() async {
        let driver = ChallengeDriver(creates: [.fixture()], polls: [])
        let service = makeService(driver: driver)

        service.start(entry: .fixture(challenge: nil), platform: .tvOS)
        service.retry()
        await service.waitForCurrentOperation()

        guard case .failed(let failure) = service.state else {
            Issue.record("Expected unsupported failure")
            return
        }
        #expect(failure.kind == .unsupported)
        #expect((await driver.snapshot()).createCount == 0)
    }

    @Test("expired challenge refreshes within the manifest budget")
    func expiredChallengeRefreshes() async {
        let driver = ChallengeDriver(
            creates: [.fixture(id: "first"), .fixture(id: "second", qr: "qr-2")],
            polls: [.init(state: .expired), .init(state: .confirmed)]
        )
        let service = makeService(driver: driver)
        let entry = LoginPlatformEntry.fixture(challenge: .fixture(maxRefreshes: 1))

        service.start(entry: entry, platform: .iOS)
        await service.waitForCurrentOperation()

        guard case .succeeded = service.state else {
            Issue.record("Expected refreshed challenge to succeed")
            return
        }
        let snapshot = await driver.snapshot()
        #expect(snapshot.createCount == 2)
        #expect(snapshot.cancelledChallengeIds.contains("first"))
        #expect(snapshot.promoteCount == 1)
    }

    @Test("a timed-out refresh cancel discards the transaction and retry starts a new one")
    func timedOutRefreshCancelRequiresNewTransaction() async {
        let driver = ChallengeDriver(
            creates: [.fixture(id: "first"), .fixture(id: "second", qr: "qr-2")],
            polls: [.init(state: .expired), .init(state: .confirmed)],
            suspendFirstCancel: true
        )
        let service = makeService(driver: driver)
        let entry = LoginPlatformEntry.fixture(challenge: .fixture(maxRefreshes: 1))

        service.start(entry: entry, platform: .tvOS)
        await service.waitForCurrentOperation()

        guard case .failed(let firstFailure) = service.state else {
            Issue.record("Expected the unconfirmed cancel to stop this transaction")
            return
        }
        #expect(firstFailure.kind == .timedOut)
        let firstSnapshot = await driver.snapshot()
        #expect(firstSnapshot.beginCount == 1)
        #expect(firstSnapshot.discardCount == 1)
        #expect(firstSnapshot.cancelledChallengeIds == ["first"])

        service.retry()
        await service.waitForCurrentOperation()

        guard case .succeeded = service.state else {
            Issue.record("Expected retry to succeed with a new transaction")
            return
        }
        let finalSnapshot = await driver.snapshot()
        #expect(finalSnapshot.beginCount == 2)
        #expect(finalSnapshot.promoteCount == 1)
        #expect(finalSnapshot.cancelledChallengeIds == ["first"])
    }

    @Test("a rejected refresh cancel discards the transaction before retry")
    func rejectedRefreshCancelRequiresNewTransaction() async {
        let driver = ChallengeDriver(
            creates: [.fixture(id: "first"), .fixture(id: "second", qr: "qr-2")],
            polls: [.init(state: .expired), .init(state: .confirmed)],
            rejectFirstCancel: true
        )
        let service = makeService(driver: driver)
        let entry = LoginPlatformEntry.fixture(challenge: .fixture(maxRefreshes: 1))

        service.start(entry: entry, platform: .tvOS)
        await service.waitForCurrentOperation()

        guard case .failed = service.state else {
            Issue.record("Expected the rejected cancel to stop this transaction")
            return
        }
        let firstSnapshot = await driver.snapshot()
        #expect(firstSnapshot.beginCount == 1)
        #expect(firstSnapshot.createCount == 1)
        #expect(firstSnapshot.discardCount == 1)
        #expect(firstSnapshot.cancelledChallengeIds == ["first"])

        service.retry()
        await service.waitForCurrentOperation()

        guard case .succeeded = service.state else {
            Issue.record("Expected retry to succeed with a fresh transaction")
            return
        }
        let finalSnapshot = await driver.snapshot()
        #expect(finalSnapshot.beginCount == 2)
        #expect(finalSnapshot.promoteCount == 1)
    }

    @Test("refresh budget exhaustion produces an expired failure")
    func refreshBudgetExhaustion() async {
        let driver = ChallengeDriver(
            creates: [.fixture()],
            polls: [.init(state: .expired)]
        )
        let service = makeService(driver: driver)
        let entry = LoginPlatformEntry.fixture(challenge: .fixture(maxRefreshes: 0))

        service.start(entry: entry, platform: .tvOS)
        await service.waitForCurrentOperation()

        guard case .failed(let failure) = service.state else {
            Issue.record("Expected expired failure")
            return
        }
        #expect(failure.kind == .expired)
        #expect(failure.canRetry)
        #expect((await driver.snapshot()).createCount == 1)
    }

    @Test("cancel invalidates a suspended create and discards its transaction")
    func cancellationRejectsLateCreate() async {
        let driver = ChallengeDriver(creates: [], polls: [], suspendFirstCreate: true)
        let service = makeService(driver: driver)

        service.start(entry: .fixture(), platform: .tvOS)
        let didSuspend = await eventually { await driver.hasSuspendedCreate() }
        #expect(didSuspend)

        service.cancel()
        await driver.resumeSuspendedCreate(with: .fixture())
        let didDiscard = await eventually { (await driver.snapshot()).discardCount > 0 }

        #expect(didDiscard)
        #expect(service.state == .idle)
        let snapshot = await driver.snapshot()
        #expect(snapshot.promoteCount == 0)
        #expect(snapshot.loginCount == 0)
    }

    private func makeService(driver: ChallengeDriver) -> PlatformLoginChallengeService {
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
        return PlatformLoginChallengeService(dependencies: .init(
            beginTransaction: { pluginId, _ in
                await driver.begin(pluginId: pluginId)
            },
            promoteTransaction: { pluginId, transactionId in
                await driver.promote(pluginId: pluginId, transactionId: transactionId)
            },
            discardTransaction: { pluginId, transactionId in
                await driver.discard(pluginId: pluginId, transactionId: transactionId)
            },
            create: { pluginId, function, request in
                try await driver.create(pluginId: pluginId, function: function, request: request)
            },
            poll: { pluginId, function, request in
                try await driver.poll(pluginId: pluginId, function: function, request: request)
            },
            submitVerification: { pluginId, function, request in
                try await driver.submitVerification(
                    pluginId: pluginId,
                    function: function,
                    request: request
                )
            },
            resendVerification: { pluginId, function, request in
                try await driver.resendVerification(
                    pluginId: pluginId,
                    function: function,
                    request: request
                )
            },
            cancel: { pluginId, function, request in
                try await driver.cancel(pluginId: pluginId, function: function, request: request)
            },
            login: { pluginId, _, cookie, uid, liveType, _ in
                await driver.login(pluginId: pluginId, cookie: cookie, uid: uid, liveType: liveType)
            },
            releaseRuntimeLease: { _, _ in },
            credentialStatus: { pluginId in
                await driver.credentialStatus(pluginId: pluginId)
            },
            didLogin: { pluginId in
                await driver.didLogin(pluginId: pluginId)
            },
            sleep: { _ in await driver.didSleep() },
            now: { fixedNow },
            cleanupPluginCallTimeout: .milliseconds(25)
        ))
    }

    private func eventually(_ predicate: () async -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if await predicate() { return true }
            await Task.yield()
        }
        return false
    }
}

private extension LoginPlatformEntry {
    static func fixture(challenge: ManifestLoginChallenge? = .fixture()) -> Self {
        Self(
            pluginId: "fixture.login",
            displayName: "Fixture",
            liveType: "fixture",
            loginFlow: .init(
                loginURL: "https://example.invalid/login",
                cookieDomains: ["example.invalid"],
                authSignalCookies: ["session"]
            ),
            loginChallenge: challenge,
            auth: nil,
            version: "1.0.0"
        )
    }
}

private extension ManifestLoginChallenge {
    static func fixture(maxRefreshes: Int = 1, minProtocol: Int = 1) -> Self {
        Self(
            kind: .qrcode,
            minLoginChallengeProtocol: minProtocol,
            pollIntervalMs: 1_000,
            timeoutSeconds: 180,
            maxRefreshes: maxRefreshes,
            hint: "Scan now",
            preferOn: ["tvos"]
        )
    }
}

private extension LoginChallengeCreateResponse {
    static func fixture(id: String = "challenge", qr: String = "qr-content") -> Self {
        Self(kind: .qrcode, challengeId: id, qrContent: qr, pollIntervalMs: 1_000)
    }
}

private actor ChallengeDriver {
    struct Snapshot: Sendable {
        let beginCount: Int
        let createCount: Int
        let promoteCount: Int
        let discardCount: Int
        let loginCount: Int
        let didLoginCount: Int
        let createFunctions: [String]
        let pollFunctions: [String]
        let cancelledChallengeIds: [String]
        let verificationSubmitCount: Int
        let verificationSubmitFunctions: [String]
        let verificationResendCount: Int
        let verificationResendFunctions: [String]
    }

    enum DriverError: Error {
        case missingCreate
        case missingPoll
        case cancelRejected
        case missingVerificationSubmit
        case missingVerificationResend
    }

    private var creates: [LoginChallengeCreateResponse]
    private var polls: [LoginChallengePollResponse]
    private var verificationSubmits: [LoginChallengeVerificationSubmitResponse]
    private var verificationResends: [LoginChallengeVerificationDescriptor]
    private var suspendFirstCreate: Bool
    private var suspendedCreate: CheckedContinuation<LoginChallengeCreateResponse, Never>?
    private let suspendedSleeps: Set<Int>
    private var sleepContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var sleepCount = 0
    private var beginCount = 0
    private var createCount = 0
    private var promoteCount = 0
    private var discardCount = 0
    private var loginCount = 0
    private var didLoginCount = 0
    private var createFunctions: [String] = []
    private var pollFunctions: [String] = []
    private var cancelledChallengeIds: [String] = []
    private var verificationSubmitCount = 0
    private var verificationSubmitFunctions: [String] = []
    private var verificationResendCount = 0
    private var verificationResendFunctions: [String] = []
    private var suspendFirstCancel: Bool
    private var rejectFirstCancel: Bool
    private var suspendedCancel: CheckedContinuation<Void, Never>?

    init(
        creates: [LoginChallengeCreateResponse],
        polls: [LoginChallengePollResponse],
        verificationSubmits: [LoginChallengeVerificationSubmitResponse] = [],
        verificationResends: [LoginChallengeVerificationDescriptor] = [],
        suspendFirstCreate: Bool = false,
        suspendFirstCancel: Bool = false,
        rejectFirstCancel: Bool = false,
        suspendedSleeps: Set<Int> = []
    ) {
        self.creates = creates
        self.polls = polls
        self.verificationSubmits = verificationSubmits
        self.verificationResends = verificationResends
        self.suspendFirstCreate = suspendFirstCreate
        self.suspendFirstCancel = suspendFirstCancel
        self.rejectFirstCancel = rejectFirstCancel
        self.suspendedSleeps = suspendedSleeps
    }

    func begin(pluginId: String) -> String {
        beginCount += 1
        return "transaction-\(beginCount)-for-\(pluginId)"
    }

    func promote(pluginId: String, transactionId: String) -> String {
        promoteCount += 1
        return "session=valid"
    }

    func discard(pluginId: String, transactionId: String) {
        discardCount += 1
    }

    func create(
        pluginId: String,
        function: String,
        request: LoginChallengeCreateRequest
    ) async throws -> LoginChallengeCreateResponse {
        createCount += 1
        createFunctions.append(function)
        if suspendFirstCreate {
            suspendFirstCreate = false
            return await withCheckedContinuation { continuation in
                suspendedCreate = continuation
            }
        }
        guard !creates.isEmpty else { throw DriverError.missingCreate }
        return creates.removeFirst()
    }

    func poll(
        pluginId: String,
        function: String,
        request: LoginChallengePollRequest
    ) throws -> LoginChallengePollResponse {
        pollFunctions.append(function)
        guard !polls.isEmpty else { throw DriverError.missingPoll }
        return polls.removeFirst()
    }

    func submitVerification(
        pluginId: String,
        function: String,
        request: LoginChallengeVerificationRequest
    ) throws -> LoginChallengeVerificationSubmitResponse {
        verificationSubmitCount += 1
        verificationSubmitFunctions.append(function)
        guard !verificationSubmits.isEmpty else { throw DriverError.missingVerificationSubmit }
        return verificationSubmits.removeFirst()
    }

    func resendVerification(
        pluginId: String,
        function: String,
        request: LoginChallengeVerificationResendRequest
    ) throws -> LoginChallengeVerificationDescriptor {
        verificationResendCount += 1
        verificationResendFunctions.append(function)
        guard !verificationResends.isEmpty else { throw DriverError.missingVerificationResend }
        return verificationResends.removeFirst()
    }

    func cancel(pluginId: String, function: String, request: LoginChallengePollRequest) async throws {
        cancelledChallengeIds.append(request.challengeId)
        if rejectFirstCancel {
            rejectFirstCancel = false
            throw DriverError.cancelRejected
        }
        if suspendFirstCancel {
            suspendFirstCancel = false
            await withCheckedContinuation { continuation in
                suspendedCancel = continuation
            }
        }
    }

    func login(
        pluginId: String,
        cookie: String,
        uid: String?,
        liveType: String
    ) -> PlatformSessionValidationResult {
        loginCount += 1
        return .valid
    }

    func credentialStatus(pluginId: String) -> CredentialStatus? {
        CredentialStatus(state: "valid", userId: "status-user", userName: "Fixture User")
    }

    func didLogin(pluginId: String) {
        didLoginCount += 1
    }

    func didSleep() async {
        sleepCount += 1
        let count = sleepCount
        guard suspendedSleeps.contains(count) else { return }
        await withCheckedContinuation { continuation in
            sleepContinuations[count] = continuation
        }
    }

    func hasSuspendedSleep(_ count: Int) -> Bool {
        sleepContinuations[count] != nil
    }

    func resumeSleep(_ count: Int) {
        sleepContinuations.removeValue(forKey: count)?.resume()
    }

    func hasSuspendedCreate() -> Bool {
        suspendedCreate != nil
    }

    func resumeSuspendedCreate(with response: LoginChallengeCreateResponse) {
        suspendedCreate?.resume(returning: response)
        suspendedCreate = nil
    }

    func snapshot() -> Snapshot {
        Snapshot(
            beginCount: beginCount,
            createCount: createCount,
            promoteCount: promoteCount,
            discardCount: discardCount,
            loginCount: loginCount,
            didLoginCount: didLoginCount,
            createFunctions: createFunctions,
            pollFunctions: pollFunctions,
            cancelledChallengeIds: cancelledChallengeIds,
            verificationSubmitCount: verificationSubmitCount,
            verificationSubmitFunctions: verificationSubmitFunctions,
            verificationResendCount: verificationResendCount,
            verificationResendFunctions: verificationResendFunctions
        )
    }
}
