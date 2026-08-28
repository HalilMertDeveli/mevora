import 'package:flutter/material.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_category.dart';

/// Material icons for Why You Matched categories (theme-aware, a11y-friendly).
abstract final class WhyYouMatchedCategoryIcons {
  static IconData forCategory(WhyYouMatchedCategory category) {
    return switch (category) {
      WhyYouMatchedCategory.humor => Icons.sentiment_satisfied_alt_rounded,
      WhyYouMatchedCategory.music => Icons.music_note_rounded,
      WhyYouMatchedCategory.interests => Icons.interests_rounded,
      WhyYouMatchedCategory.lifestyle => Icons.self_improvement_rounded,
      WhyYouMatchedCategory.preferences => Icons.translate_rounded,
      WhyYouMatchedCategory.communication => Icons.forum_rounded,
      WhyYouMatchedCategory.distance => Icons.place_rounded,
      WhyYouMatchedCategory.relationship => Icons.favorite_rounded,
      WhyYouMatchedCategory.questions => Icons.psychology_rounded,
    };
  }

  static IconData forWire(String? wire) {
    final category = WhyYouMatchedCategoryX.tryParse(wire);
    if (category == null) {
      return Icons.check_circle_outline_rounded;
    }
    return forCategory(category);
  }
}
