import Foundation

/// One step of an engine's output. `newlySettled` is text that is final
/// from now on and follows everything settled before; `provisional` is the
/// engine's current guess for what comes after it and replaces the previous
/// guess completely.
public struct CaptionUpdate: Sendable, Equatable {
    public var newlySettled: String
    public var provisional: String

    public init(newlySettled: String = "", provisional: String = "") {
        self.newlySettled = newlySettled
        self.provisional = provisional
    }
}

/// A speech engine fed with live sound. One instance = one run: `start`,
/// any number of `feed`, `stop`.
public protocol CaptionEngine: AnyObject {
    /// Called with every change, on an arbitrary queue.
    var onUpdate: (@Sendable (CaptionUpdate) -> Void)? { get set }
    /// Called once if the engine dies while running.
    var onError: (@Sendable (Error) -> Void)? { get set }

    func start() async throws
    /// Mono Float32 at `SystemAudioTap.sampleRate`. Safe from any queue.
    func feed(_ samples: [Float])
    func stop() async
}
