import Foundation
import Testing

@testable import AngelLiveCore

@Suite("Plugin login transaction Cookie jar")
struct LoginTransactionStoreTests {
    @Test("cookies honor host, domain, secure flag, and RFC path boundaries")
    func cookieScoping() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        try await store.absorb(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            setCookieHeaders: [
                "root=one; Path=/",
                "account=two; Path=/account; Secure",
                "shared=three; Domain=example.com; Path=/"
            ],
            responseURL: try #require(URL(string: "https://login.example.com/start"))
        )

        let accountHeader = try await store.cookieHeader(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            for: URL(string: "https://login.example.com/account/profile")
        )
        #expect(accountHeader.contains("account=two"))
        #expect(accountHeader.contains("root=one"))
        #expect(accountHeader.contains("shared=three"))
        #expect(accountHeader.hasPrefix("account=two"))

        let siblingHeader = try await store.cookieHeader(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            for: URL(string: "https://api.example.com/account")
        )
        #expect(!siblingHeader.contains("root=one"))
        #expect(!siblingHeader.contains("account=two"))
        #expect(siblingHeader.contains("shared=three"))

        let wrongPathHeader = try await store.cookieHeader(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            for: URL(string: "https://login.example.com/accounting")
        )
        #expect(!wrongPathHeader.contains("account=two"))

        let insecureHeader = try await store.cookieHeader(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            for: URL(string: "http://login.example.com/account")
        )
        #expect(!insecureHeader.contains("account=two"))
    }

    @Test("response cookies reject unrelated domains and public suffixes")
    func responseDomainValidation() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        try await store.absorb(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            setCookieHeaders: [
                "parent=allowed; Domain=example.com; Path=/",
                "foreign=blocked; Domain=evil.com; Path=/",
                "topLevel=blocked; Domain=com; Path=/"
            ],
            responseURL: try #require(URL(string: "https://login.example.com/start"))
        )
        try await store.absorb(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            setCookieHeaders: [
                "countryParent=allowed; Domain=example.co.uk; Path=/",
                "countrySuffix=blocked; Domain=co.uk; Path=/"
            ],
            responseURL: try #require(URL(string: "https://login.example.co.uk/start"))
        )
        try await store.absorb(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            setCookieHeaders: [
                "privateSuffix=blocked; Domain=github.io; Path=/",
                "privateTenant=allowed; Domain=tenant.github.io; Path=/"
            ],
            responseURL: try #require(URL(string: "https://login.tenant.github.io/start"))
        )

        let promoted = try await store.promote(pluginId: "fixture.plugin", transactionId: transactionId)
        #expect(promoted.contains("parent=allowed"))
        #expect(promoted.contains("countryParent=allowed"))
        #expect(!promoted.contains("foreign="))
        #expect(!promoted.contains("topLevel="))
        #expect(!promoted.contains("countrySuffix="))
        #expect(!promoted.contains("privateSuffix="))
        #expect(promoted.contains("privateTenant=allowed"))
    }

    @Test("secure Cookie prefixes are enforced before entering the transaction")
    func secureCookiePrefixes() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        try await store.absorb(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            setCookieHeaders: [
                "__Host-valid=one; Secure; Path=/",
                "__Host-domain=blocked; Secure; Path=/; Domain=example.com",
                "__Host-path=blocked; Secure; Path=/account",
                "__Host-insecure=blocked; Path=/",
                "__Secure-valid=two; Secure; Path=/",
                "__Secure-insecure=blocked; Path=/"
            ],
            responseURL: try #require(URL(string: "https://login.example.com/start"))
        )
        try await store.absorb(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            setCookieHeaders: ["secureFromHTTP=blocked; Secure; Path=/"],
            responseURL: try #require(URL(string: "http://login.example.com/start"))
        )

        let header = try await store.cookieHeader(pluginId: "fixture.plugin", transactionId: transactionId)
        #expect(header.contains("__Host-valid=one"))
        #expect(header.contains("__Secure-valid=two"))
        #expect(!header.contains("__Host-domain="))
        #expect(!header.contains("__Host-path="))
        #expect(!header.contains("__Host-insecure="))
        #expect(!header.contains("__Secure-insecure="))
        #expect(!header.contains("secureFromHTTP="))
    }

    @Test("transaction ownership is enforced for every operation")
    func ownership() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "owner.plugin")

        await #expect(throws: LoginTransactionError.ownershipMismatch) {
            _ = try await store.cookieHeader(
                pluginId: "other.plugin",
                transactionId: transactionId
            )
        }
        await #expect(throws: LoginTransactionError.ownershipMismatch) {
            try await store.seed(
                pluginId: "other.plugin",
                transactionId: transactionId,
                cookies: ["device": "foreign"],
                domain: "example.com"
            )
        }
        await #expect(throws: LoginTransactionError.ownershipMismatch) {
            _ = try await store.promote(
                pluginId: "other.plugin",
                transactionId: transactionId
            )
        }
        #expect(try await store.cookieHeader(pluginId: "owner.plugin", transactionId: transactionId).isEmpty)
    }

    @Test("beginning a new transaction invalidates the plugin's previous generation")
    func oneActiveTransactionPerPlugin() async throws {
        let store = LoginTransactionStore()
        let first = try await store.begin(pluginId: "fixture.plugin")
        let second = try await store.begin(pluginId: "fixture.plugin")

        #expect(first != second)
        await #expect(throws: LoginTransactionError.notFound) {
            try await store.seed(
                pluginId: "fixture.plugin",
                transactionId: first,
                cookies: ["late": "value"],
                domain: "example.com"
            )
        }
        try await store.seed(
            pluginId: "fixture.plugin",
            transactionId: second,
            cookies: ["current": "value"],
            domain: "example.com"
        )
        #expect(try await store.cookieHeader(pluginId: "fixture.plugin", transactionId: second) == "current=value")
    }

    @Test("transaction identifiers are exact opaque capabilities")
    func transactionIdentifierIsExact() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        try await store.seed(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            cookies: ["current": "value"],
            domain: "example.com"
        )

        await #expect(throws: LoginTransactionError.notFound) {
            _ = try await store.cookieHeader(
                pluginId: "fixture.plugin",
                transactionId: transactionId.uppercased()
            )
        }
        await #expect(throws: LoginTransactionError.invalidTransactionId) {
            try await store.discard(
                pluginId: "fixture.plugin",
                transactionId: " \(transactionId) "
            )
        }

        #expect(
            try await store.cookieHeader(
                pluginId: "fixture.plugin",
                transactionId: transactionId
            ) == "current=value"
        )
        try await store.discard(pluginId: "fixture.plugin", transactionId: transactionId)
    }

    @Test("promote serializes all scoped cookies then destroys the jar")
    func promoteDestroysTransaction() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        try await store.seed(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            cookies: ["device": "one"],
            domain: "auth.example.com",
            path: "/device"
        )
        try await store.seed(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            cookies: ["session": "two"],
            domain: "api.example.com"
        )

        let promoted = try await store.promote(pluginId: "fixture.plugin", transactionId: transactionId)
        #expect(promoted.contains("device=one"))
        #expect(promoted.contains("session=two"))
        await #expect(throws: LoginTransactionError.notFound) {
            _ = try await store.cookieHeader(pluginId: "fixture.plugin", transactionId: transactionId)
        }
    }

    @Test("promotion rejects conflicting values for the same scoped Cookie name")
    func promoteRejectsAmbiguousCookieNames() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        try await store.seed(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            cookies: ["sid": "auth-account"],
            domain: "auth.example.com"
        )
        try await store.seed(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            cookies: ["sid": "api-account"],
            domain: "api.example.com"
        )

        await #expect(throws: LoginTransactionError.ambiguousCookieName) {
            _ = try await store.promote(
                pluginId: "fixture.plugin",
                transactionId: transactionId
            )
        }
        // A failed promotion does not make a secret copy; the state machine's
        // normal cleanup path still owns and can destroy the original jar.
        try await store.discard(pluginId: "fixture.plugin", transactionId: transactionId)
    }

    @Test("hard timeout destroys the transaction", .timeLimit(.minutes(1)))
    func hardTimeout() async throws {
        let store = LoginTransactionStore(hardTimeout: .milliseconds(5))
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        try await Task.sleep(for: .milliseconds(30))

        do {
            _ = try await store.cookieHeader(pluginId: "fixture.plugin", transactionId: transactionId)
            Issue.record("expected expired transaction to be unavailable")
        } catch let error as LoginTransactionError {
            #expect(error == .notFound || error == .expired)
        }
    }

    @Test("combined Set-Cookie preserves an Expires comma and separates cookie fields")
    func combinedSetCookieParsing() {
        let fields = LoginTransactionStore.splitCombinedSetCookieHeader(
            "first=one; Expires=Wed, 09 Jun 2032 10:18:14 GMT; Path=/, second=two; Path=/"
        )

        #expect(fields.count == 2)
        #expect(fields[0].contains("Expires=Wed, 09 Jun 2032"))
        #expect(fields[1] == "second=two; Path=/")
    }

    @Test("JavaScript Host session bridge can seed but cannot read transaction Cookies")
    func hostSessionBridge() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        let runtime = JSRuntime(pluginId: "fixture.plugin", loginTransactionStore: store)
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe(input) {
                await Host.session.seedTransactionCookies(
                  input.transactionId,
                  { device: "generated", numeric: 42 },
                  { domain: "example.com", path: "/login", secure: true }
                );
                return {
                  supported: Host.capabilities.loginTransaction === true,
                  credentialExposure: Host.capabilities.credentialExposure,
                  readable: await Host.session.getTransactionCookieHeader(input.transactionId)
                    .then(function () { return true; })
                    .catch(function () { return false; })
                };
              }
            };
            """)

        let value = try await runtime.callPluginFunction(
            name: "probe",
            payload: ["transactionId": transactionId]
        )
        let result = try #require(value as? [String: Any])
        #expect(result["supported"] as? Bool == true)
        #expect(result["credentialExposure"] as? Bool == false)
        #expect(result["readable"] as? Bool == false)
        let cookie = try await store.cookieHeader(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            for: URL(string: "https://example.com/login")
        )
        #expect(cookie.contains("device=generated"))
        #expect(cookie.contains("numeric=42"))
    }

    @Test("legacy Host session getter never exposes any platform credential")
    func legacyHostSessionCredentialIsUnavailable() async throws {
        let owner = "owner-\(UUID().uuidString.lowercased()).plugin"
        let other = "other-\(UUID().uuidString.lowercased()).plugin"
        let ownerSnapshot = LiveParsePlatformSessionVault.session(for: owner)
        let otherSnapshot = LiveParsePlatformSessionVault.session(for: other)
        defer {
            LiveParsePlatformSessionVault.restore(platformId: owner, session: ownerSnapshot)
            LiveParsePlatformSessionVault.restore(platformId: other, session: otherSnapshot)
        }
        LiveParsePlatformSessionVault.update(platformId: owner, cookie: "ownerSecret=one", uid: nil)
        LiveParsePlatformSessionVault.update(platformId: other, cookie: "otherSecret=two", uid: nil)

        let runtime = JSRuntime(pluginId: owner)
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              probe() {
                var ownReadable = true;
                var otherReadable = true;
                try { Host.session.getCookieHeader("\(owner)"); } catch (_) { ownReadable = false; }
                try { Host.session.getCookieHeader("\(other)"); } catch (_) { otherReadable = false; }
                return {
                  ownReadable: ownReadable,
                  otherReadable: otherReadable
                };
              }
            };
            """)
        let value = try await runtime.callPluginFunction(name: "probe")
        let result = try #require(value as? [String: Any])
        #expect(result["ownReadable"] as? Bool == false)
        #expect(result["otherReadable"] as? Bool == false)
    }

    @Test("candidate validation runtime is isolated from concurrent committed-session calls")
    func candidateCredentialRuntimeIsolation() async throws {
        let owner = "candidate-isolation-\(UUID().uuidString.lowercased()).plugin"
        let vaultSnapshot = LiveParsePlatformSessionVault.session(for: owner)
        defer { LiveParsePlatformSessionVault.restore(platformId: owner, session: vaultSnapshot) }
        LiveParsePlatformSessionVault.update(
            platformId: owner,
            cookie: "session=committed",
            uid: "old-user"
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let candidate = LiveParsePlatformSession(
            cookie: "session=candidate",
            uid: "new-user",
            updatedAt: .now
        )
        let candidateRuntime = JSRuntime(
            pluginId: owner,
            session: session,
            nativeStream: nil,
            loginTransactionStore: .shared,
            credentialDomains: ["login-transaction.invalid"],
            platformSessionOverride: candidate,
            logHandler: nil
        )
        let businessRuntime = JSRuntime(
            pluginId: owner,
            session: session,
            credentialDomains: ["login-transaction.invalid"]
        )
        let candidatePath = "/capture-candidate-\(UUID().uuidString.lowercased())"
        let businessPath = "/capture-business-\(UUID().uuidString.lowercased())"
        LoginTransactionURLProtocol.resetCapturedHeaders(for: candidatePath)
        LoginTransactionURLProtocol.resetCapturedHeaders(for: businessPath)
        let script = """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe(input) {
                var response = await Host.http.request({
                  url: "https://login-transaction.invalid" + input.path,
                  authMode: "platform_cookie",
                  platformId: "\(owner)"
                });
                var readable = true;
                try { Host.session.getCookieHeader("\(owner)"); } catch (_) { readable = false; }
                return { readable: readable, body: response.bodyText };
              }
            };
            """
        try await candidateRuntime.evaluate(script: script)
        try await businessRuntime.evaluate(script: script)

        async let candidateValue = candidateRuntime.callPluginFunction(
            name: "probe",
            payload: ["path": candidatePath]
        )
        async let businessValue = businessRuntime.callPluginFunction(
            name: "probe",
            payload: ["path": businessPath]
        )
        let candidateResult = try #require(try await candidateValue as? [String: Any])
        let businessResult = try #require(try await businessValue as? [String: Any])

        #expect(candidateResult["readable"] as? Bool == false)
        #expect(businessResult["readable"] as? Bool == false)
        #expect(candidateResult["body"] as? String == "ok")
        #expect(businessResult["body"] as? String == "ok")
        #expect(LoginTransactionURLProtocol.capturedHeader(
            named: "Cookie",
            for: candidatePath
        )?.contains("session=candidate") == true)
        #expect(LoginTransactionURLProtocol.capturedHeader(
            named: "Cookie",
            for: businessPath
        )?.contains("session=committed") == true)
        #expect(LiveParsePlatformSessionVault.session(for: owner)?.cookie == "session=committed")
        #expect(LiveParsePlatformSessionVault.session(for: owner)?.uid == "old-user")
    }

    @Test("login_transaction HTTP merges Cookie precedence and absorbs repeated Set-Cookie")
    func hostHTTPBridge() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        try await store.seed(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            cookies: ["jar": "original", "shared": "from-jar"],
            domain: "login-transaction.invalid"
        )

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let runtime = JSRuntime(
            pluginId: "fixture.plugin",
            session: session,
            loginTransactionStore: store
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe(input) {
                return await Host.http.request({
                  url: "https://login-transaction.invalid/capture-direct-private",
                  method: "GET",
                  headers: { Cookie: "jar=explicit; plugin=two" },
                  authMode: "login_transaction",
                  transactionId: input.transactionId,
                  singleFlightKey: "must-be-ignored",
                  successCacheTTLms: 60000
                });
              }
            };
            """)

        let value = try await runtime.callPluginFunction(
            name: "probe",
            payload: ["transactionId": transactionId]
        )
        let response = try #require(value as? [String: Any])
        #expect(response["bodyText"] as? String == "ok")
        let sentCookie = try #require(LoginTransactionURLProtocol.capturedHeader(
            named: "Cookie",
            for: "/capture-direct-private"
        ))
        #expect(sentCookie.contains("jar=explicit"))
        #expect(!sentCookie.contains("jar=original"))
        #expect(sentCookie.contains("shared=from-jar"))
        #expect(sentCookie.contains("plugin=two"))

        let setCookies = try #require(response["setCookies"] as? [String])
        #expect(setCookies.isEmpty)
        let headers = try #require(response["headers"] as? [String: String])
        #expect(!headers.keys.contains { $0.caseInsensitiveCompare("Set-Cookie") == .orderedSame })

        let callbackCookie = try await store.cookieHeader(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            for: URL(string: "https://login-transaction.invalid/callback/result")
        )
        #expect(callbackCookie.contains("server=three"))
        #expect(callbackCookie.contains("callback=four"))
    }

    @Test("redirect hops are absorbed before the redirected request is sent")
    func redirectCookies() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let runtime = JSRuntime(
            pluginId: "fixture.plugin",
            session: session,
            loginTransactionStore: store
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe(input) {
                return await Host.http.request({
                  url: "https://login-transaction.invalid/redirect-start",
                  authMode: "login_transaction",
                  transactionId: input.transactionId
                });
              }
            };
            """)

        let value = try await runtime.callPluginFunction(
            name: "probe",
            payload: ["transactionId": transactionId]
        )
        let response = try #require(value as? [String: Any])
        #expect(response["status"] as? Int == 200)
        #expect(response["bodyText"] as? String == "ok")
        #expect(LoginTransactionURLProtocol.capturedHeader(
            named: "Cookie",
            for: "/redirect-final"
        )?.contains("hop=middle") == true)
        let setCookies = try #require(response["setCookies"] as? [String])
        #expect(setCookies.isEmpty)
    }

    @Test("followRedirects false returns the 3xx response after absorbing its Cookie")
    func stopsRedirects() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let runtime = JSRuntime(
            pluginId: "fixture.plugin",
            session: session,
            loginTransactionStore: store
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe(input) {
                return await Host.http.request({
                  url: "https://login-transaction.invalid/manual-redirect",
                  authMode: "login_transaction",
                  transactionId: input.transactionId,
                  followRedirects: false
                });
              }
            };
            """)

        let value = try await runtime.callPluginFunction(
            name: "probe",
            payload: ["transactionId": transactionId]
        )
        let response = try #require(value as? [String: Any])
        #expect(response["status"] as? Int == 302)
        let transactionCookie = try await store.cookieHeader(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            for: URL(string: "https://login-transaction.invalid/redirect-final")
        )
        #expect(transactionCookie.contains("hop=middle"))
    }

    @Test("cross-origin redirects never forward the plugin's explicit Cookie header")
    func crossOriginRedirectDoesNotLeakExplicitCookie() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let runtime = JSRuntime(
            pluginId: "fixture.plugin",
            session: session,
            loginTransactionStore: store
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe(input) {
                return await Host.http.request({
                  url: "https://login-transaction.invalid/cross-start",
                  headers: {
                    Cookie: "explicitSecret=must-not-leak",
                    "X-Token": "header-token-must-not-leak",
                    "X-CSRF": "csrf-must-not-leak",
                    "X-Auth": "generic-auth-must-not-leak",
                    Credential: "credential-must-not-leak"
                  },
                  authMode: "login_transaction",
                  transactionId: input.transactionId
                });
              }
            };
            """)

        let value = try await runtime.callPluginFunction(
            name: "probe",
            payload: ["transactionId": transactionId]
        )
        let response = try #require(value as? [String: Any])
        let echoedCookie = (response["bodyText"] as? String) ?? ""
        #expect(!echoedCookie.contains("explicitSecret"))
        #expect(!echoedCookie.contains("initialHostOnly"))
        #expect(!echoedCookie.contains("header-token-must-not-leak"))
        #expect(!echoedCookie.contains("csrf-must-not-leak"))
        #expect(!echoedCookie.contains("generic-auth-must-not-leak"))
        #expect(!echoedCookie.contains("credential-must-not-leak"))
    }

    @Test("managed authentication requests bypass system cookies and URLCache")
    func managedAuthenticationRequestPolicy() async throws {
        let owner = "managed-policy-\(UUID().uuidString.lowercased()).plugin"
        let vaultSnapshot = LiveParsePlatformSessionVault.session(for: owner)
        defer { LiveParsePlatformSessionVault.restore(platformId: owner, session: vaultSnapshot) }
        LiveParsePlatformSessionVault.update(platformId: owner, cookie: "vaultSession=secret", uid: nil)

        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: owner)
        try await store.seed(
            pluginId: owner,
            transactionId: transactionId,
            cookies: ["transactionSession": "secret"],
            domain: "login-transaction.invalid"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let runtime = JSRuntime(
            pluginId: owner,
            session: session,
            loginTransactionStore: store,
            credentialDomains: ["login-transaction.invalid"]
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe(input) {
                var platform = await Host.http.request({
                  url: "https://login-transaction.invalid/policy-platform",
                  authMode: "platform_cookie",
                  platformId: "\(owner)"
                });
                var transaction = await Host.http.request({
                  url: "https://login-transaction.invalid/policy-transaction",
                  authMode: "login_transaction",
                  transactionId: input.transactionId
                });
                var injected = await Host.http.request({
                  url: "https://login-transaction.invalid/policy-injected",
                  platformId: "\(owner)",
                  cookieInject: [{
                    cookieName: "vaultSession",
                    target: "header",
                    headerName: "X-Vault"
                  }]
                });
                return [platform.bodyText, transaction.bodyText, injected.bodyText];
              }
            };
            """)

        let value = try await runtime.callPluginFunction(
            name: "probe",
            payload: ["transactionId": transactionId]
        )
        let policies = try #require(value as? [String])
        #expect(policies.count == 3)
        #expect(policies[0].contains("handlesCookies=false"))
        #expect(policies[0].contains("reloadIgnoringCache=true"))
        #expect(policies[0].contains("vaultSession=secret"))
        #expect(policies[1].contains("handlesCookies=false"))
        #expect(policies[1].contains("reloadIgnoringCache=true"))
        #expect(policies[1].contains("transactionSession=secret"))
        #expect(policies[2].contains("handlesCookies=false"))
        #expect(policies[2].contains("reloadIgnoringCache=true"))
        #expect(policies[2].contains("injected=secret"))
    }

    @Test("managed credential responses cannot seed URLCache for a later anonymous request")
    func managedResponseIsNotCached() async throws {
        let owner = "managed-cache-\(UUID().uuidString.lowercased()).plugin"
        let path = "/cacheable-\(UUID().uuidString.lowercased())"
        let url = "https://login-transaction.invalid\(path)"
        let vaultSnapshot = LiveParsePlatformSessionVault.session(for: owner)
        defer { LiveParsePlatformSessionVault.restore(platformId: owner, session: vaultSnapshot) }
        LiveParsePlatformSessionVault.update(platformId: owner, cookie: "cacheSecret=must-not-persist", uid: nil)
        LoginTransactionURLProtocol.resetCacheableRequestCount(for: path)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        configuration.urlCache = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0)
        configuration.requestCachePolicy = .useProtocolCachePolicy
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let runtime = JSRuntime(
            pluginId: owner,
            session: session,
            credentialDomains: ["login-transaction.invalid"]
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe() {
                var managed = await Host.http.request({
                  url: "\(url)",
                  authMode: "platform_cookie",
                  platformId: "\(owner)"
                });
                var anonymous = await Host.http.request({ url: "\(url)" });
                return [managed.bodyText, anonymous.bodyText];
              }
            };
            """)

        let value = try await runtime.callPluginFunction(name: "probe")
        let bodies = try #require(value as? [String])
        #expect(bodies[0].contains("cacheSecret=must-not-persist"))
        #expect(!bodies[1].contains("cacheSecret=must-not-persist"))
        #expect(bodies[1].contains("hit=2"))
        #expect(LoginTransactionURLProtocol.cacheableRequestCount(for: path) == 2)
    }

    @Test("cross-origin redirects strip platform and dynamically injected credential headers")
    func managedCrossOriginRedirectStripsCredentials() async throws {
        let owner = "managed-redirect-\(UUID().uuidString.lowercased()).plugin"
        let vaultSnapshot = LiveParsePlatformSessionVault.session(for: owner)
        defer { LiveParsePlatformSessionVault.restore(platformId: owner, session: vaultSnapshot) }
        LiveParsePlatformSessionVault.update(
            platformId: owner,
            cookie: "vaultSession=redirect-secret",
            uid: nil
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let runtime = JSRuntime(
            pluginId: owner,
            session: session,
            credentialDomains: ["login-transaction.invalid"]
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe() {
                var platform = await Host.http.request({
                  url: "https://login-transaction.invalid/cross-start",
                  headers: { "X-Token": "plugin-secret" },
                  authMode: "platform_cookie",
                  platformId: "\(owner)"
                });
                var injected = await Host.http.request({
                  url: "https://login-transaction.invalid/cross-start",
                  platformId: "\(owner)",
                  cookieInject: [{
                    cookieName: "vaultSession",
                    target: "header",
                    headerName: "X-Token"
                  }]
                });
                return [platform.bodyText, injected.bodyText];
              }
            };
            """)

        let value = try await runtime.callPluginFunction(name: "probe")
        let bodies = try #require(value as? [String])
        #expect(bodies.count == 2)
        #expect(!bodies[0].contains("redirect-secret"))
        #expect(!bodies[0].contains("plugin-secret"))
        #expect(!bodies[1].contains("redirect-secret"))
    }

    @Test("managed credentials reject non-loopback cleartext HTTP")
    func managedCredentialsRequireHTTPS() async throws {
        let owner = "managed-http-\(UUID().uuidString.lowercased()).plugin"
        let vaultSnapshot = LiveParsePlatformSessionVault.session(for: owner)
        defer { LiveParsePlatformSessionVault.restore(platformId: owner, session: vaultSnapshot) }
        LiveParsePlatformSessionVault.update(platformId: owner, cookie: "secret=value", uid: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let runtime = JSRuntime(
            pluginId: owner,
            session: session,
            credentialDomains: ["login-transaction.invalid"]
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe() {
                try {
                  await Host.http.request({
                    url: "http://login-transaction.invalid/policy-platform",
                    authMode: "platform_cookie",
                    platformId: "\(owner)"
                  });
                  return { rejected: false };
                } catch (_) {
                  return { rejected: true };
                }
              }
            };
            """)

        let value = try await runtime.callPluginFunction(name: "probe")
        #expect((value as? [String: Any])?["rejected"] as? Bool == true)
    }

    @Test("committed credentials are restricted to manifest-declared domains")
    func managedCredentialsRequireDeclaredDomain() async throws {
        let owner = "managed-domain-\(UUID().uuidString.lowercased()).plugin"
        let path = "/capture-disallowed-\(UUID().uuidString.lowercased())"
        let vaultSnapshot = LiveParsePlatformSessionVault.session(for: owner)
        defer { LiveParsePlatformSessionVault.restore(platformId: owner, session: vaultSnapshot) }
        LiveParsePlatformSessionVault.update(platformId: owner, cookie: "secret=value", uid: nil)
        LoginTransactionURLProtocol.resetCapturedHeaders(for: path)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let runtime = JSRuntime(
            pluginId: owner,
            session: session,
            credentialDomains: ["login-transaction.invalid"]
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe() {
                try {
                  await Host.http.request({
                    url: "https://login-transaction-other.invalid\(path)",
                    authMode: "platform_cookie",
                    platformId: "\(owner)"
                  });
                  return { rejected: false };
                } catch (_) {
                  return { rejected: true };
                }
              }
            };
            """)

        let value = try await runtime.callPluginFunction(name: "probe")
        #expect((value as? [String: Any])?["rejected"] as? Bool == true)
        #expect(LoginTransactionURLProtocol.capturedHeader(named: "Cookie", for: path) == nil)
    }

    @Test("query credential injection is never reflected in the JavaScript response URL")
    func injectedQueryCredentialIsNotReflected() async throws {
        let owner = "managed-query-\(UUID().uuidString.lowercased()).plugin"
        let path = "/capture-query-\(UUID().uuidString.lowercased())"
        let vaultSnapshot = LiveParsePlatformSessionVault.session(for: owner)
        defer { LiveParsePlatformSessionVault.restore(platformId: owner, session: vaultSnapshot) }
        LiveParsePlatformSessionVault.update(
            platformId: owner,
            cookie: "accessToken=query-secret",
            uid: nil
        )
        LoginTransactionURLProtocol.resetCapturedHeaders(for: path)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let runtime = JSRuntime(
            pluginId: owner,
            session: session,
            credentialDomains: ["login-transaction.invalid"]
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe() {
                return await Host.http.request({
                  url: "https://login-transaction.invalid\(path)?public=value",
                  platformId: "\(owner)",
                  cookieInject: [{
                    cookieName: "accessToken",
                    target: "query",
                    queryName: "token"
                  }]
                });
              }
            };
            """)

        let value = try await runtime.callPluginFunction(name: "probe")
        let response = try #require(value as? [String: Any])
        let visibleURL = try #require(response["url"] as? String)
        #expect(!visibleURL.contains("query-secret"))
        #expect(!visibleURL.contains("?"))
        #expect(LoginTransactionURLProtocol.capturedURL(for: path)?.contains("token=query-secret") == true)
    }

    @Test("loopback HTTP cannot redirect a transaction Cookie to cleartext remote HTTP")
    func loopbackRedirectCannotEscapeToCleartextRemoteHost() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        try await store.seed(
            pluginId: "fixture.plugin",
            transactionId: transactionId,
            cookies: ["session": "must-stay-private"],
            domain: "login-transaction.invalid"
        )
        LoginTransactionURLProtocol.resetCleartextRedirectHitCount()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let runtime = JSRuntime(
            pluginId: "fixture.plugin",
            session: session,
            loginTransactionStore: store
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe(input) {
                return await Host.http.request({
                  url: "http://127.0.0.1/loopback-redirect",
                  authMode: "login_transaction",
                  transactionId: input.transactionId,
                  timeoutMs: 100
                });
              }
            };
            """)

        do {
            _ = try await runtime.callPluginFunction(
                name: "probe",
                payload: ["transactionId": transactionId]
            )
            Issue.record("Expected an unsafe redirect to be rejected")
        } catch {
            // Expected: the host rejects before URLSession follows the hop.
        }
        #expect(LoginTransactionURLProtocol.cleartextRedirectHitCount == 0)
        #expect(await store.isActive(pluginId: "fixture.plugin", transactionId: transactionId))
    }

    @Test("custom login function console payloads are recursively redacted")
    func recursiveConsoleRedaction() throws {
        let original: [String: Any] = [
            "wrapper": [
                "transactionId": "transaction-secret",
                "challengeId": "challenge-secret",
                "qrContent": "qr-secret",
                "url": "https://example.com/poll?token=query-secret#fragment",
                "nested": [[
                    "Cookie": "session=cookie-secret",
                    "accessToken": "token-secret",
                    "state": "waiting"
                ]]
            ]
        ]

        #expect(LiveParsePluginManager.containsLoginTransactionIdentifier(original))
        let redacted = LiveParsePluginManager.redactedLoginTransactionConsoleValue(original)
        let data = try JSONSerialization.data(withJSONObject: redacted)
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(!text.contains("transaction-secret"))
        #expect(!text.contains("challenge-secret"))
        #expect(!text.contains("qr-secret"))
        #expect(!text.contains("query-secret"))
        #expect(!text.contains("cookie-secret"))
        #expect(!text.contains("token-secret"))
        #expect(text.contains("waiting"))
        #expect(text.contains("<redacted>"))

        let promotedCredential: [String: Any] = [
            "credential": ["cookie": "promoted-secret", "uid": "user-secret"]
        ]
        #expect(LiveParsePluginManager.containsSensitiveConsoleValue(promotedCredential))
        let credentialText = try #require(String(
            data: JSONSerialization.data(
                withJSONObject: LiveParsePluginManager.redactedLoginTransactionConsoleValue(promotedCredential)
            ),
            encoding: .utf8
        ))
        #expect(!credentialText.contains("promoted-secret"))
    }

    @Test("sensitive runtime sections suppress arbitrary JavaScript console strings")
    func sensitiveRuntimeConsoleSuppression() async throws {
        let recorder = RuntimeLogRecorder()
        let runtime = JSRuntime(pluginId: "fixture.plugin", logHandler: { message in
            recorder.append(message)
        })
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              probe(input) {
                console.log("token embedded in text: " + input.secret);
                return { ok: true };
              }
            };
            """)

        await runtime.beginSensitiveLoggingSuppression()
        _ = try await runtime.callPluginFunction(name: "probe", payload: ["secret": "must-not-log"])
        await runtime.endSensitiveLoggingSuppression()
        #expect(!recorder.messages.contains { $0.contains("must-not-log") })

        _ = try await runtime.callPluginFunction(name: "probe", payload: ["secret": "visible-after-section"])
        #expect(recorder.messages.contains { $0.contains("visible-after-section") })
    }

    @Test(
        "cancelling a never-settling JavaScript Promise releases the caller and host continuation",
        .timeLimit(.minutes(1))
    )
    func pendingPromiseCancellation() async throws {
        let runtime = JSRuntime(pluginId: "fixture.plugin")
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              never() { return new Promise(function () {}); },
              probe() { return { ok: true }; }
            };
            """)

        let call = Task<Void, Error> {
            _ = try await runtime.callPluginFunction(name: "never")
        }
        #expect(await eventually {
            await runtime.pendingPromiseCallCountForTesting() == 1
        })

        call.cancel()
        let result = await call.result
        switch result {
        case .success:
            Issue.record("Expected the cancelled Promise call to throw")
        case .failure(let error):
            #expect(error is CancellationError)
        }
        #expect(await eventually {
            await runtime.pendingPromiseCallCountForTesting() == 0
        })

        let probe = try await runtime.callPluginFunction(name: "probe")
        #expect((probe as? [String: Any])?["ok"] as? Bool == true)
    }

    @Test(
        "abandoning a sensitive runtime cancels host HTTP and clamps plugin timeout",
        .timeLimit(.minutes(1))
    )
    func abandonedRuntimeCancelsHostHTTP() async throws {
        LoginTransactionURLProtocol.resetStalledRequestState()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let runtime = JSRuntime(pluginId: "fixture.plugin", session: session)
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe() {
                return await Host.http.request({
                  url: "https://login-transaction.invalid/stalled",
                  timeout: 999999999
                });
              }
            };
            """)

        let call = Task<Void, Error> {
            _ = try await runtime.callPluginFunction(name: "probe")
        }
        #expect(await eventually {
            LoginTransactionURLProtocol.stalledStartCount == 1
        })
        #expect(LoginTransactionURLProtocol.stalledTimeout <= 120)

        call.cancel()
        await runtime.abandonInFlightOperations()
        _ = await call.result
        #expect(await eventually {
            LoginTransactionURLProtocol.stalledStopCount == 1
        })
    }

    @Test("login_transaction bypasses both single-flight joining and response cache")
    func loginHTTPAlwaysPerformsRealRequests() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LoginTransactionURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let runtime = JSRuntime(
            pluginId: "fixture.plugin",
            session: session,
            loginTransactionStore: store
        )
        try await runtime.evaluate(script: """
            globalThis.LiveParsePlugin = {
              apiVersion: 1,
              async probe(input) {
                var options = {
                  url: "https://login-transaction.invalid/unique",
                  authMode: "login_transaction",
                  transactionId: input.transactionId,
                  singleFlightKey: "same-key",
                  successCacheTTLms: 60000
                };
                var responses = await Promise.all([
                  Host.http.request(options),
                  Host.http.request(options)
                ]);
                var third = await Host.http.request(options);
                return [responses[0].bodyText, responses[1].bodyText, third.bodyText];
              }
            };
            """)

        let value = try await runtime.callPluginFunction(
            name: "probe",
            payload: ["transactionId": transactionId]
        )
        let bodies = try #require(value as? [String])
        #expect(bodies.count == 3)
        #expect(Set(bodies).count == 3)
    }

    @Test("discarded transactions reject late response absorption")
    func discardedTransactionRejectsLateAbsorption() async throws {
        let store = LoginTransactionStore()
        let transactionId = try await store.begin(pluginId: "fixture.plugin")
        try await store.discard(pluginId: "fixture.plugin", transactionId: transactionId)

        await #expect(throws: LoginTransactionError.notFound) {
            try await store.absorb(
                pluginId: "fixture.plugin",
                transactionId: transactionId,
                setCookieHeaders: ["late=secret; Path=/"],
                responseURL: URL(string: "https://example.com/callback")!
            )
        }
    }

    private func eventually(_ predicate: () async -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if await predicate() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }
}

private final class RuntimeLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var messages: [String] {
        lock.withLock { storage }
    }

    func append(_ message: String) {
        lock.withLock { storage.append(message) }
    }
}

private final class LoginTransactionURLProtocol: URLProtocol {
    private static let countLock = NSLock()
    private nonisolated(unsafe) static var cacheableCounts: [String: Int] = [:]
    private nonisolated(unsafe) static var capturedHeaders: [String: [String: String]] = [:]
    private nonisolated(unsafe) static var capturedURLs: [String: String] = [:]
    private nonisolated(unsafe) static var cleartextRedirectHits = 0
    private nonisolated(unsafe) static var stalledStarts = 0
    private nonisolated(unsafe) static var stalledStops = 0
    private nonisolated(unsafe) static var observedStalledTimeout: TimeInterval = 0

    static func resetCacheableRequestCount(for path: String) {
        countLock.withLock { cacheableCounts[path] = 0 }
    }

    static func cacheableRequestCount(for path: String) -> Int {
        countLock.withLock { cacheableCounts[path] ?? 0 }
    }

    static func resetCapturedHeaders(for path: String) {
        countLock.withLock {
            capturedHeaders.removeValue(forKey: path)
            capturedURLs.removeValue(forKey: path)
        }
    }

    static func capturedHeader(named name: String, for path: String) -> String? {
        countLock.withLock {
            capturedHeaders[path]?.first {
                $0.key.caseInsensitiveCompare(name) == .orderedSame
            }?.value
        }
    }

    static func capturedURL(for path: String) -> String? {
        countLock.withLock { capturedURLs[path] }
    }

    static func resetCleartextRedirectHitCount() {
        countLock.withLock { cleartextRedirectHits = 0 }
    }

    static var cleartextRedirectHitCount: Int {
        countLock.withLock { cleartextRedirectHits }
    }

    static func resetStalledRequestState() {
        countLock.withLock {
            stalledStarts = 0
            stalledStops = 0
            observedStalledTimeout = 0
        }
    }

    static var stalledStartCount: Int {
        countLock.withLock { stalledStarts }
    }

    static var stalledStopCount: Int {
        countLock.withLock { stalledStops }
    }

    static var stalledTimeout: TimeInterval {
        countLock.withLock { observedStalledTimeout }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "login-transaction.invalid"
            || request.url?.host == "login-transaction-other.invalid"
            || request.url?.host == "127.0.0.1"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.countLock.withLock {
            Self.capturedHeaders[url.path] = request.allHTTPHeaderFields ?? [:]
            Self.capturedURLs[url.path] = url.absoluteString
        }

        if url.path == "/stalled" {
            Self.countLock.withLock {
                Self.stalledStarts += 1
                Self.observedStalledTimeout = request.timeoutInterval
            }
            return
        }

        if url.path == "/loopback-redirect" {
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": "http://login-transaction.invalid/cleartext-final"]
            ), let redirectURL = URL(string: "http://login-transaction.invalid/cleartext-final") else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(
                self,
                wasRedirectedTo: URLRequest(url: redirectURL),
                redirectResponse: response
            )
            return
        }

        if url.path == "/cleartext-final" {
            Self.countLock.withLock { Self.cleartextRedirectHits += 1 }
        }

        if url.path == "/redirect-start" {
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Location": "https://login-transaction.invalid/redirect-final",
                    "Set-Cookie": "hop=middle; Path=/"
                ]
            ), let redirectURL = URL(string: "https://login-transaction.invalid/redirect-final") else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            var redirectedRequest = URLRequest(url: redirectURL)
            redirectedRequest.httpMethod = request.httpMethod
            for (name, value) in request.allHTTPHeaderFields ?? [:] {
                redirectedRequest.setValue(value, forHTTPHeaderField: name)
            }
            client?.urlProtocol(
                self,
                wasRedirectedTo: redirectedRequest,
                redirectResponse: response
            )
            return
        }

        if url.path == "/cross-start" {
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 307,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Location": "https://login-transaction-other.invalid/cross-final",
                    "Set-Cookie": "initialHostOnly=one; Path=/"
                ]
            ), let redirectURL = URL(string: "https://login-transaction-other.invalid/cross-final") else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            var redirectedRequest = URLRequest(url: redirectURL)
            redirectedRequest.httpMethod = request.httpMethod
            for (name, value) in request.allHTTPHeaderFields ?? [:] {
                redirectedRequest.setValue(value, forHTTPHeaderField: name)
            }
            client?.urlProtocol(
                self,
                wasRedirectedTo: redirectedRequest,
                redirectResponse: response
            )
            return
        }

        if url.path == "/manual-redirect" {
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Location": "https://login-transaction.invalid/redirect-final",
                    "Set-Cookie": "hop=middle; Path=/"
                ]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if url.path == "/unique" {
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(UUID().uuidString.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if url.path.hasPrefix("/policy-") {
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "text/plain"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let body = """
            handlesCookies=\(request.httpShouldHandleCookies);\
            reloadIgnoringCache=\(request.cachePolicy == .reloadIgnoringLocalCacheData);\
            cookie=\(request.value(forHTTPHeaderField: "Cookie") ?? "");\
            injected=\(request.value(forHTTPHeaderField: "X-Vault") ?? "")
            """
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if url.path.hasPrefix("/cacheable-") {
            let hit = Self.countLock.withLock {
                let next = (Self.cacheableCounts[url.path] ?? 0) + 1
                Self.cacheableCounts[url.path] = next
                return next
            }
            guard let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/plain",
                    "Cache-Control": "public, max-age=3600"
                ]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            let body = "hit=\(hit);cookie=\(request.value(forHTTPHeaderField: "Cookie") ?? "")"
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let setCookie = url.path == "/redirect-final" || url.path == "/cross-final"
            ? "final=ready; Path=/"
            : "server=three; Path=/, callback=four; Path=/callback"
        guard
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "text/plain; charset=utf-8",
                    "Set-Cookie": setCookie
                ]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let responseBody: String
        if url.path.hasPrefix("/capture-") || url.path == "/redirect-final" {
            responseBody = "ok"
        } else {
            let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
            responseBody = [
                cookie,
                request.value(forHTTPHeaderField: "X-Token") ?? "",
                request.value(forHTTPHeaderField: "X-CSRF") ?? "",
                request.value(forHTTPHeaderField: "X-Auth") ?? "",
                request.value(forHTTPHeaderField: "Credential") ?? ""
            ].joined(separator: "|")
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        guard request.url?.path == "/stalled" else { return }
        Self.countLock.withLock { Self.stalledStops += 1 }
    }
}
