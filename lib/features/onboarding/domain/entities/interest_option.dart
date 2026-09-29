import 'package:flutter/material.dart';
import 'package:mevora/core/theme/mevora_icons.dart';

class InterestOption {
  const InterestOption({
    required this.id,
    required this.icon,
  });

  final String id;
  final IconData icon;
}

abstract final class InterestCatalog {
  static const options = <InterestOption>[
    InterestOption(id: 'music', icon: MevoraIcons.track),
    InterestOption(id: 'travel', icon: MevoraIcons.travel),
    InterestOption(id: 'fitness', icon: MevoraIcons.fitness),
    InterestOption(id: 'food', icon: MevoraIcons.food),
    InterestOption(id: 'art', icon: MevoraIcons.art),
    InterestOption(id: 'movies', icon: MevoraIcons.film),
    InterestOption(id: 'books', icon: MevoraIcons.books),
    InterestOption(id: 'gaming', icon: MevoraIcons.gaming),
    InterestOption(id: 'nature', icon: MevoraIcons.outdoors),
    InterestOption(id: 'photography', icon: MevoraIcons.camera),
    InterestOption(id: 'coffee', icon: MevoraIcons.coffee),
    InterestOption(id: 'dancing', icon: MevoraIcons.nightlife),
    InterestOption(id: 'yoga', icon: MevoraIcons.wellbeing),
    InterestOption(id: 'tech', icon: MevoraIcons.tech),
    InterestOption(id: 'fashion', icon: MevoraIcons.fashion),
    InterestOption(id: 'pets', icon: MevoraIcons.pets),
    InterestOption(id: 'sports', icon: MevoraIcons.sports),
    InterestOption(id: 'cooking', icon: MevoraIcons.cooking),
  ];

  static InterestOption? find(String id) {
    for (final option in options) {
      if (option.id == id) {
        return option;
      }
    }
    return null;
  }
}
