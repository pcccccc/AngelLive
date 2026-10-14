import Foundation

/// A resource category within an HLS stream. Offsets are relative to one resource.
public enum LiveTransformTarget: String, Codable, Sendable, Equatable {
    case segment
}

public enum LiveKeygenAlgorithm: String, Codable, Sendable, Equatable {
    case xorshift32
}

/// Errors deliberately omit wire values, including key material.
public enum LiveMediaTransformError: Error, LocalizedError, Sendable, Equatable {
    case invalidConfiguration
    case invalidScope
    case invalidKeygen
    case invalidTargets
    case invalidOffset

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "Invalid media transform configuration."
        case .invalidScope: "Invalid media transform scope."
        case .invalidKeygen: "Invalid media transform key generator."
        case .invalidTargets: "Invalid media transform targets."
        case .invalidOffset: "Invalid media transform resource offset."
        }
    }
}

public struct LiveTransformScope: Codable, Sendable, Equatable {
    public let offsetInPeriod: Int
    public let lengthPerPeriod: Int
    public let periodBytes: Int
    /// Zero transforms every period up to the end of the resource.
    public let periodCount: Int

    public init(offsetInPeriod: Int, lengthPerPeriod: Int, periodBytes: Int, periodCount: Int) throws {
        self.offsetInPeriod = offsetInPeriod
        self.lengthPerPeriod = lengthPerPeriod
        self.periodBytes = periodBytes
        self.periodCount = periodCount
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case offsetInPeriod, lengthPerPeriod, periodBytes, periodCount
    }

    public init(from decoder: Decoder) throws {
        do {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                offsetInPeriod: c.decode(Int.self, forKey: .offsetInPeriod),
                lengthPerPeriod: c.decode(Int.self, forKey: .lengthPerPeriod),
                periodBytes: c.decode(Int.self, forKey: .periodBytes),
                periodCount: c.decode(Int.self, forKey: .periodCount)
            )
        } catch {
            throw LiveMediaTransformError.invalidScope
        }
    }

    fileprivate func validate() throws {
        guard offsetInPeriod >= 0, lengthPerPeriod > 0, periodBytes > 0, periodCount >= 0 else {
            throw LiveMediaTransformError.invalidScope
        }
        let intervalEnd = offsetInPeriod.addingReportingOverflow(lengthPerPeriod)
        guard !intervalEnd.overflow, intervalEnd.partialValue <= periodBytes,
              Int64(exactly: periodBytes) != nil else {
            throw LiveMediaTransformError.invalidScope
        }
        if periodCount > 0 {
            let span = Int64(periodBytes).multipliedReportingOverflow(by: Int64(periodCount))
            guard !span.overflow else { throw LiveMediaTransformError.invalidScope }
        }
    }
}

public struct LiveKeygenSpec: Codable, Sendable, Equatable {
    public let algorithm: LiveKeygenAlgorithm
    public let seed: UInt32
    public let saltBias: UInt32
    public let saltMultiplier: UInt32
    public let shiftLeftA: UInt8
    public let shiftRight: UInt8
    public let shiftLeftB: UInt8
    public let zeroState: UInt32
    public let zeroKeyByte: UInt8
    /// If false, only transformed bytes advance one continuous state sequence.
    public let resetPerPeriod: Bool

    public init(
        algorithm: LiveKeygenAlgorithm = .xorshift32,
        seed: UInt32,
        saltBias: UInt32,
        saltMultiplier: UInt32,
        shiftLeftA: UInt8,
        shiftRight: UInt8,
        shiftLeftB: UInt8,
        zeroState: UInt32,
        zeroKeyByte: UInt8,
        resetPerPeriod: Bool
    ) throws {
        self.algorithm = algorithm
        self.seed = seed
        self.saltBias = saltBias
        self.saltMultiplier = saltMultiplier
        self.shiftLeftA = shiftLeftA
        self.shiftRight = shiftRight
        self.shiftLeftB = shiftLeftB
        self.zeroState = zeroState
        self.zeroKeyByte = zeroKeyByte
        self.resetPerPeriod = resetPerPeriod
        try validate()
    }

    private enum CodingKeys: String, CodingKey {
        case algorithm, seed, saltBias, saltMultiplier, shiftLeftA, shiftRight, shiftLeftB
        case zeroState, zeroKeyByte, resetPerPeriod
    }

    public init(from decoder: Decoder) throws {
        do {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                algorithm: c.decode(LiveKeygenAlgorithm.self, forKey: .algorithm),
                seed: c.decode(UInt32.self, forKey: .seed),
                saltBias: c.decode(UInt32.self, forKey: .saltBias),
                saltMultiplier: c.decode(UInt32.self, forKey: .saltMultiplier),
                shiftLeftA: c.decode(UInt8.self, forKey: .shiftLeftA),
                shiftRight: c.decode(UInt8.self, forKey: .shiftRight),
                shiftLeftB: c.decode(UInt8.self, forKey: .shiftLeftB),
                zeroState: c.decode(UInt32.self, forKey: .zeroState),
                zeroKeyByte: c.decode(UInt8.self, forKey: .zeroKeyByte),
                resetPerPeriod: c.decode(Bool.self, forKey: .resetPerPeriod)
            )
        } catch {
            throw LiveMediaTransformError.invalidKeygen
        }
    }

    fileprivate func validate() throws {
        guard (1...31).contains(shiftLeftA), (1...31).contains(shiftRight),
              (1...31).contains(shiftLeftB) else {
            throw LiveMediaTransformError.invalidKeygen
        }
    }

    fileprivate func initialState(period: Int64) -> UInt32 {
        let state = seed ^ ((UInt32(truncatingIfNeeded: period) &+ saltBias) &* saltMultiplier)
        return state == 0 ? zeroState : state
    }

    fileprivate func next(_ state: UInt32) -> UInt32 {
        var value = state
        value ^= value << shiftLeftA
        value ^= value >> shiftRight
        value ^= value << shiftLeftB
        return value
    }
}

/// Declarative byte restoration. Applying it twice restores the input.
public struct LiveMediaTransform: Codable, Sendable, Equatable {
    public let scope: LiveTransformScope
    public let keygen: LiveKeygenSpec
    public let targets: [LiveTransformTarget]

    public init(scope: LiveTransformScope, keygen: LiveKeygenSpec, targets: [LiveTransformTarget] = [.segment]) throws {
        self.scope = scope
        self.keygen = keygen
        self.targets = targets
        _ = try validated()
    }

    private enum CodingKeys: String, CodingKey { case scope, keygen, targets }

    public init(from decoder: Decoder) throws {
        do {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                scope: c.decode(LiveTransformScope.self, forKey: .scope),
                keygen: c.decode(LiveKeygenSpec.self, forKey: .keygen),
                targets: c.contains(.targets) ? c.decode([LiveTransformTarget].self, forKey: .targets) : [.segment]
            )
        } catch let error as LiveMediaTransformError {
            throw error
        } catch {
            throw LiveMediaTransformError.invalidConfiguration
        }
    }

    @discardableResult
    public func validated() throws -> Self {
        try scope.validate()
        try keygen.validate()
        guard !targets.isEmpty, Set(targets.map(\.rawValue)).count == targets.count else {
            throw LiveMediaTransformError.invalidTargets
        }
        return self
    }

    public func apply(to bytes: inout [UInt8], at absoluteOffset: Int64, target: LiveTransformTarget = .segment) throws {
        try bytes.withUnsafeMutableBufferPointer {
            try apply(to: $0, at: absoluteOffset, target: target)
        }
    }

    /// The buffer belongs to one resource; absoluteOffset is within that resource,
    /// even when its HTTP request uses a byte range in a larger backing object.
    public func apply(to bytes: UnsafeMutableBufferPointer<UInt8>, at absoluteOffset: Int64, target: LiveTransformTarget = .segment) throws {
        guard absoluteOffset >= 0,
              !absoluteOffset.addingReportingOverflow(Int64(bytes.count)).overflow else {
            throw LiveMediaTransformError.invalidOffset
        }
        guard targets.contains(target), !bytes.isEmpty else { return }
        let periodBytes = Int64(scope.periodBytes)
        let windowStart = Int64(scope.offsetInPeriod)
        let windowEnd = windowStart + Int64(scope.lengthPerPeriod)
        let end = absoluteOffset + Int64(bytes.count)
        var cursor = absoluteOffset
        var continuousState: UInt32?

        while cursor < end {
            let period = cursor / periodBytes
            if scope.periodCount > 0, period >= Int64(scope.periodCount) { break }
            let localOffset = cursor % periodBytes
            if localOffset < windowStart {
                cursor += min(windowStart - localOffset, end - cursor)
                continue
            }
            if localOffset >= windowEnd {
                cursor += min(periodBytes - localOffset, end - cursor)
                continue
            }

            let precedingBytes = keygen.resetPerPeriod
                ? localOffset - windowStart
                : period * Int64(scope.lengthPerPeriod) + localOffset - windowStart
            var state = continuousState ?? jump(
                keygen.initialState(period: keygen.resetPerPeriod ? period : 0),
                steps: UInt64(precedingBytes)
            )
            let count = min(windowEnd - localOffset, end - cursor)
            let startIndex = Int(cursor - absoluteOffset)
            for index in startIndex..<(startIndex + Int(count)) {
                state = keygen.next(state)
                let lowByte = UInt8(truncatingIfNeeded: state)
                bytes[index] ^= lowByte == 0 ? keygen.zeroKeyByte : lowByte
            }
            if !keygen.resetPerPeriod { continuousState = state }
            cursor += count
        }
    }

    /// Each column is the image of one bit under the xorshift linear map.
    /// Squaring that map skips 2^n states, so a seek costs O(log offset).
    private func jump(_ initialState: UInt32, steps: UInt64) -> UInt32 {
        guard steps > 0 else { return initialState }
        var columns = (0..<32).map { keygen.next(UInt32(1) << $0) }
        var remaining = steps
        var state = initialState
        while remaining > 0 {
            if remaining & 1 != 0 { state = Self.multiply(columns, state) }
            remaining >>= 1
            if remaining > 0 { columns = columns.map { Self.multiply(columns, $0) } }
        }
        return state
    }

    private static func multiply(_ columns: [UInt32], _ vector: UInt32) -> UInt32 {
        var value = vector
        var result: UInt32 = 0
        while value != 0 {
            result ^= columns[value.trailingZeroBitCount]
            value &= value &- 1
        }
        return result
    }
}
