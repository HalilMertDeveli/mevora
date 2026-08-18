enum LocationScreenState {
  prompt,
  locating,
  preparingMatches,
  success,
  denied,
  deniedForever,
  restricted,
  serviceDisabled,
  reducedAccuracy,
  error,
}

extension LocationScreenStateX on LocationScreenState {
  bool get isLoading =>
      this == LocationScreenState.locating ||
      this == LocationScreenState.preparingMatches;
}
