import 'package:flutter/material.dart';
import 'package:mevora/core/extensions/string_extensions.dart';

class MevoraAvatar extends StatelessWidget {
  const MevoraAvatar({
    super.key,
    this.image,
    this.name,
    this.size = 56,
    this.isVerified = false,
  });

  final ImageProvider? image;
  final String? name;
  final double size;
  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final initials = (name ?? '').initials;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: size / 2,
            backgroundColor: colors.primaryContainer,
            foregroundColor: colors.onPrimaryContainer,
            backgroundImage: image,
            child: image == null
                ? Text(
                    initials.isEmpty ? '?' : initials,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: size * 0.32,
                    ),
                  )
                : null,
          ),
          if (isVerified)
            Positioned(
              right: -2,
              bottom: -2,
              child: Semantics(
                label: 'Verified',
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.verified,
                    size: size * 0.32,
                    color: colors.tertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
