import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/localization/l10n_format.dart';
import 'package:mevora/core/theme/app_colors.dart';
import 'package:mevora/core/theme/app_decorations.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/core/theme/app_shadows.dart';
import 'package:mevora/core/theme/mevora_icons.dart';
import 'package:mevora/features/compatibility/presentation/widgets/compatibility_signal.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_boost_badge.dart';
import 'package:mevora/features/discovery/presentation/widgets/discovery_network_image.dart';
import 'package:mevora/features/picks/domain/entities/mevora_pick.dart';
import 'package:mevora/features/picks/presentation/copy/pick_copy.dart';
import 'package:mevora/features/picks/presentation/widgets/pick_type_badge.dart';
import 'package:mevora/l10n/app_localizations.dart';
import 'package:mevora/shared/widgets/mevora_button.dart';

/// One Mevora Pick: who, and why Mevora chose them — then the decision.
///
/// Built like the Discover card (full-bleed portrait under the photo scrim,
/// serif name, place), with the reason and the compatibility ring below it
/// rather than over the photo.
class PickCard extends StatelessWidget {
  const PickCard({
    super.key,
    required this.pick,
    required this.onOpen,
    required this.onLike,
    required this.onPass,
    this.busy = false,
    this.maxHeight,
  });

  /// The portrait's shape when the card has all the room it wants.
  static const double photoAspectRatio = 4 / 4.2;

  /// The flattest the portrait is cropped to. Any flatter and the badge, the
  /// name and the face start to crowd each other; past this the card is
  /// allowed to outgrow [maxHeight] instead.
  static const double flattestPhotoAspectRatio = 3 / 2;

  final MevoraPick pick;
  final VoidCallback onOpen;
  final VoidCallback onLike;
  final VoidCallback onPass;

  /// A decision for this Pick is in flight.
  final bool busy;

  /// The room the list has for the whole card, when it wants the decision on
  /// screen together with the portrait. Only the portrait gives up height for
  /// it, and only down to [flattestPhotoAspectRatio]; the reason and the
  /// Pass / Like buttons keep theirs.
  final double? maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.palette;
    final l10n = AppLocalizations.of(context);
    final candidate = pick.candidate;
    final supporting = PickCopy.supportingLine(l10n, pick);
    final distance = candidate.distanceKm != null
        ? L10nFormat.distance(l10n, candidate.distanceKm!)
        : candidate.distanceLabel;
    final place = [
      if (candidate.city != null && candidate.city!.isNotEmpty) candidate.city!,
      if (distance != null && distance.isNotEmpty) distance,
    ].join(' · ');
    final nameLine = candidate.age > 0
        ? '${candidate.displayName}, ${candidate.age}'
        : candidate.displayName;
    final radius = BorderRadius.circular(AppRadii.card);
    final secondary = pick.secondaryLabels.take(2).toList();

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: p.surface,
        boxShadow: AppShadows.discoveryCard(theme.brightness),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Material(
          type: MaterialType.transparency,
          child: _PhotoOverDetails(
            maxHeight: maxHeight,
            photo: Semantics(
              button: true,
              label: l10n.picksOpenProfileSemantics(candidate.displayName),
              child: InkWell(
                onTap: onOpen,
                child: SizedBox.expand(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (candidate.cardPhoto == null)
                        const PhotoUnavailablePlaceholder()
                      else
                        DiscoveryNetworkImage(url: candidate.cardPhoto!),
                      IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: AppDecorations.photoScrim(),
                          ),
                        ),
                      ),
                      Positioned(
                        top: AppSpacing.md,
                        left: AppSpacing.md,
                        right: AppSpacing.md,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: PickTypeBadge(
                                  type: pick.pickType,
                                  onMedia: true,
                                ),
                              ),
                            ),
                            if (candidate.isBoosted) ...[
                              const SizedBox(width: AppSpacing.sm),
                              const DiscoveryBoostBadge(),
                            ],
                          ],
                        ),
                      ),
                      Positioned(
                        left: AppSpacing.s20,
                        right: AppSpacing.s20,
                        bottom: AppSpacing.md,
                        child: _Identity(
                          name: nameLine,
                          place: place,
                          verified: candidate.isVerified,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            details: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.s20,
                    AppSpacing.md,
                    AppSpacing.s20,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              PickCopy.headline(l10n, pick),
                              style: theme.textTheme.titleMedium,
                            ),
                            if (supporting != null) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                supporting,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                            if (secondary.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.s12),
                              Wrap(
                                spacing: AppSpacing.xs + 2,
                                runSpacing: AppSpacing.xs + 2,
                                children: [
                                  for (final label in secondary)
                                    PickTypeBadge(
                                      type: label,
                                      emphasized: false,
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      // The score is a quiet ring at the edge, as on Discover:
                      // the reason leads, the number supports it.
                      if (candidate.compatibilityScore > 0) ...[
                        const SizedBox(width: AppSpacing.md),
                        CompatibilityRing(score: candidate.compatibilityScore),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.sm,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  child: PickDecisionBar(
                    name: candidate.displayName,
                    busy: busy,
                    onLike: onLike,
                    onPass: onPass,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card's two parts, portrait above and reason + decision below.
///
/// A Column cannot do this: the portrait has to take what the details leave,
/// but never less than its flattest shape. So the details are laid out first
/// at their own height, and the portrait is sized from what is left of
/// [maxHeight] — between [PickCard.flattestPhotoAspectRatio] and
/// [PickCard.photoAspectRatio]. Without a [maxHeight] the portrait simply
/// has its full shape, as it always had.
class _PhotoOverDetails extends MultiChildRenderObjectWidget {
  _PhotoOverDetails({
    required this.maxHeight,
    required Widget photo,
    required Widget details,
  }) : super(children: [photo, details]);

  final double? maxHeight;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderPhotoOverDetails(maxHeight: maxHeight);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPhotoOverDetails renderObject,
  ) {
    renderObject.maxHeight = maxHeight;
  }
}

class _PhotoOverDetailsParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPhotoOverDetails extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PhotoOverDetailsParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _PhotoOverDetailsParentData
        > {
  _RenderPhotoOverDetails({double? maxHeight}) : _maxHeight = maxHeight;

  double? _maxHeight;
  double? get maxHeight => _maxHeight;
  set maxHeight(double? value) {
    if (value == _maxHeight) {
      return;
    }
    _maxHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PhotoOverDetailsParentData) {
      child.parentData = _PhotoOverDetailsParentData();
    }
  }

  double _photoHeight(double width, double detailsHeight) {
    final natural = width / PickCard.photoAspectRatio;
    final limit = _maxHeight;
    if (limit == null || !limit.isFinite) {
      return natural;
    }
    final floor = width / PickCard.flattestPhotoAspectRatio;
    return (limit - detailsHeight).clamp(floor, natural);
  }

  Size _layout(BoxConstraints constraints, {required bool dry}) {
    final photo = firstChild!;
    final details = childAfter(photo)!;
    final width = constraints.maxWidth;
    final detailsConstraints = BoxConstraints.tightFor(width: width);
    final detailsSize = dry
        ? details.getDryLayout(detailsConstraints)
        : (details..layout(detailsConstraints, parentUsesSize: true)).size;
    final photoHeight = _photoHeight(width, detailsSize.height);
    if (!dry) {
      photo.layout(BoxConstraints.tightFor(width: width, height: photoHeight));
      (photo.parentData! as _PhotoOverDetailsParentData).offset = Offset.zero;
      (details.parentData! as _PhotoOverDetailsParentData).offset = Offset(
        0,
        photoHeight,
      );
    }
    return constraints.constrain(Size(width, photoHeight + detailsSize.height));
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return _layout(constraints, dry: true);
  }

  @override
  void performLayout() {
    size = _layout(constraints, dry: false);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    defaultPaint(context, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    return defaultHitTestChildren(result, position: position);
  }
}

/// Name, age and place over the portrait, set like the Discover card.
class _Identity extends StatelessWidget {
  const _Identity({
    required this.name,
    required this.place,
    required this.verified,
  });

  final String name;
  final String place;
  final bool verified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: AppColors.onMedia,
                ),
              ),
            ),
            if (verified) ...[
              const SizedBox(width: AppSpacing.sm),
              Icon(
                MevoraIcons.verified,
                size: 22,
                color: AppColors.onMedia,
                semanticLabel: l10n.profileVerifiedBadge,
              ),
            ],
          ],
        ),
        if (place.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xxs),
          Row(
            children: [
              const Icon(
                MevoraIcons.location,
                size: 16,
                color: AppColors.onMediaMuted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.onMediaMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Pass / Like, shared by the card and the profile page.
class PickDecisionBar extends StatelessWidget {
  const PickDecisionBar({
    super.key,
    required this.name,
    required this.onLike,
    required this.onPass,
    this.busy = false,
  });

  final String name;
  final VoidCallback onLike;
  final VoidCallback onPass;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            button: true,
            enabled: !busy,
            label: l10n.picksPassSemantics(name),
            excludeSemantics: true,
            child: MevoraButton(
              label: l10n.picksPass,
              icon: MevoraIcons.pass,
              variant: MevoraButtonVariant.secondary,
              maxLines: 1,
              onPressed: busy ? null : onPass,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Semantics(
            button: true,
            enabled: !busy,
            label: l10n.picksLikeSemantics(name),
            excludeSemantics: true,
            child: MevoraButton(
              label: l10n.picksLike,
              icon: MevoraIcons.like,
              maxLines: 1,
              isLoading: busy,
              onPressed: busy ? null : onLike,
            ),
          ),
        ),
      ],
    );
  }
}
