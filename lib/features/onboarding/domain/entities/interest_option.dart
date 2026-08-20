import 'package:flutter/material.dart';

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
    InterestOption(id: 'music', icon: Icons.music_note_outlined),
    InterestOption(id: 'travel', icon: Icons.flight_takeoff_outlined),
    InterestOption(id: 'fitness', icon: Icons.fitness_center_outlined),
    InterestOption(id: 'food', icon: Icons.restaurant_outlined),
    InterestOption(id: 'art', icon: Icons.palette_outlined),
    InterestOption(id: 'movies', icon: Icons.movie_outlined),
    InterestOption(id: 'books', icon: Icons.menu_book_outlined),
    InterestOption(id: 'gaming', icon: Icons.sports_esports_outlined),
    InterestOption(id: 'nature', icon: Icons.park_outlined),
    InterestOption(id: 'photography', icon: Icons.photo_camera_outlined),
    InterestOption(id: 'coffee', icon: Icons.coffee_outlined),
    InterestOption(id: 'dancing', icon: Icons.nightlife_outlined),
    InterestOption(id: 'yoga', icon: Icons.self_improvement_outlined),
    InterestOption(id: 'tech', icon: Icons.memory_outlined),
    InterestOption(id: 'fashion', icon: Icons.checkroom_outlined),
    InterestOption(id: 'pets', icon: Icons.pets_outlined),
    InterestOption(id: 'sports', icon: Icons.sports_soccer_outlined),
    InterestOption(id: 'cooking', icon: Icons.soup_kitchen_outlined),
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
