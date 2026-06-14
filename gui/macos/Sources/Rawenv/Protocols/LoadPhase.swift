import Foundation

/// The lifecycle of an async data fetch on a screen. Views switch on this to
/// show a loading indicator, a helpful empty state, an error state with retry,
/// or the loaded content — so a blank screen can never be mistaken for "no
/// data" and "no data" can never be mistaken for "fetch failed".
public enum LoadPhase: Equatable, Sendable {
    /// Nothing requested yet (initial value before `.task`/`load()` runs).
    case idle
    /// A fetch is in flight.
    case loading
    /// The fetch succeeded and produced at least one item.
    case loaded
    /// The fetch succeeded but produced no data — show guidance, not an error.
    case empty
    /// The fetch threw. Carries the real error message for display + Retry.
    case failed(String)

    public var isLoading: Bool { self == .loading }
    public var isEmpty: Bool { self == .empty }
    public var isLoaded: Bool { self == .loaded }

    /// The error message when in the `.failed` state, otherwise `nil`.
    public var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}
