/// Discover compatibility badge presentation state.
enum CompatibilityDisplayStatus {
  /// Score is being resolved (viewer profile or engine).
  calculating,

  /// A real score is available for display.
  ready,

  /// Not enough data to compute a meaningful score.
  unavailable,
}
