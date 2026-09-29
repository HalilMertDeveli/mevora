import 'package:flutter/widgets.dart';
import 'package:mevora/core/analytics/analytics_provider.dart';
import 'package:mevora/features/relationship_learning/data/relationship_learning_analytics.dart';
import 'package:mevora/features/relationship_learning/domain/repositories/relationship_learning_repository.dart';

/// Provides Relationship Learning (and the reset of learned preferences) to
/// onboarding, Picks, Profile and Settings.
class RelationshipLearningScope extends InheritedWidget {
  const RelationshipLearningScope({
    super.key,
    required this.repository,
    required super.child,
    this.analyticsProvider,
  });

  final RelationshipLearningRepository repository;
  final AnalyticsProvider? analyticsProvider;

  RelationshipLearningAnalytics get analytics =>
      RelationshipLearningAnalytics(analyticsProvider);

  static RelationshipLearningScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<RelationshipLearningScope>();
  }

  @override
  bool updateShouldNotify(RelationshipLearningScope oldWidget) {
    return repository != oldWidget.repository ||
        analyticsProvider != oldWidget.analyticsProvider;
  }
}
