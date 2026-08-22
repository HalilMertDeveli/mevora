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
          ClipOval(
            child: ColoredBox(
              color: colors.primaryContainer,
              child: image == null
                  ? Center(
                      child: Text(
                        initials.isEmpty ? '?' : initials,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: size * 0.32,
                          color: colors.onPrimaryContainer,
                        ),
                      ),
                    )
                  : Image(
                      image: image!,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) {
                        return Center(
                          child: Text(
                            initials.isEmpty ? '?' : initials,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: size * 0.32,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        );
                      },
                    ),
            ),
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
