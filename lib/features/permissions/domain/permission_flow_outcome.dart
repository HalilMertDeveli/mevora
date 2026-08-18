enum PermissionFlowOutcome {
  granted,
  limited,
  denied,
  skipped,
  settingsOpened,
}

extension PermissionFlowOutcomeX on PermissionFlowOutcome {
  bool get isUsable =>
      this == PermissionFlowOutcome.granted ||
      this == PermissionFlowOutcome.limited;
}
