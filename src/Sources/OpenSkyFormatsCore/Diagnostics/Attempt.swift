import Foundation

nonisolated private let recoveredFailureLog = EngineLogger(
    subsystem: "nl.jjgroenendijk.opensky",
    category: "RecoveredFailure"
)

/// Runs a call whose failure the caller survives. On failure it logs the error with the
/// call site and returns nil, so no error is lost (`docs/decisions/error-handling.md`).
@discardableResult
nonisolated public func attempt<T>(
    file: StaticString = #fileID,
    line: UInt = #line,
    _ body: () throws -> T
) -> T? {
    do {
        return try body()
    } catch {
        logRecovered(error, file: file, line: line)
        return nil
    }
}

/// The same for a call that returns an optional, so the result is not nested.
@discardableResult
nonisolated public func attempt<T>(
    file: StaticString = #fileID,
    line: UInt = #line,
    _ body: () throws -> T?
) -> T? {
    do {
        return try body()
    } catch {
        logRecovered(error, file: file, line: line)
        return nil
    }
}

/// The same for a read of a file that may not exist, such as a cache entry. A missing
/// file gives nil without a log line; any other failure is logged.
@discardableResult
nonisolated public func attemptIfPresent<T>(
    file: StaticString = #fileID,
    line: UInt = #line,
    _ body: () throws -> T
) -> T? {
    do {
        return try body()
    } catch where isMissingFile(error) {
        return nil
    } catch {
        logRecovered(error, file: file, line: line)
        return nil
    }
}

/// The same for a call that returns an optional.
@discardableResult
nonisolated public func attemptIfPresent<T>(
    file: StaticString = #fileID,
    line: UInt = #line,
    _ body: () throws -> T?
) -> T? {
    do {
        return try body()
    } catch where isMissingFile(error) {
        return nil
    } catch {
        logRecovered(error, file: file, line: line)
        return nil
    }
}

nonisolated private func logRecovered(_ error: any Error, file: StaticString, line: UInt) {
    recoveredFailureLog.warning("\(file):\(line): \(error)")
}

nonisolated func isMissingFile(_ error: any Error) -> Bool {
    let error = error as NSError
    switch error.domain {
    case NSCocoaErrorDomain:
        return error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError
    case NSPOSIXErrorDomain:
        return error.code == Int(ENOENT)
    default:
        return false
    }
}

/// The same for an `async` call.
@discardableResult
nonisolated(nonsending) public func attempt<T>(
    file: StaticString = #fileID,
    line: UInt = #line,
    _ body: () async throws -> T
) async -> T? {
    do {
        return try await body()
    } catch {
        logRecovered(error, file: file, line: line)
        return nil
    }
}

nonisolated extension SingleValueDecodingContainer {
    /// The value when it has this type, or nil when it has another. A value of one of
    /// several types is decoded by trying each, so a type mismatch is expected. Any other
    /// decoding error is thrown.
    public func decodeIfType<T: Decodable>(_ type: T.Type) throws -> T? {
        do {
            return try decode(type)
        } catch DecodingError.typeMismatch {
            return nil
        }
    }
}
