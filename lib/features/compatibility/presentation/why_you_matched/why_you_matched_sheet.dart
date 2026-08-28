import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mevora/core/constants/app_spacings.dart';
import 'package:mevora/core/responsive/responsive.dart';
import 'package:mevora/core/theme/app_radii.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_reason.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_result.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/why_you_matched_reasons_panel.dart';
import 'package:mevora/features/compatibility/presentation/why_you_matched/why_you_matched_ui_status.dart';

/// Opens a scrollable bottom sheet for Why You Matched reasons.
///
/// Uses [ResponsiveValue.heightFraction] + safe-area padding — no fixed
/// pixel heights that overflow on 360×640.
Future<void> showWhyYouMatchedSheet(
  BuildContext context, {
  required WhyYouMatchedUiStatus status,
  WhyYouMatchedResult? result,
  List<WhyYouMatchedReason>? reasons,
  String? message,
  VoidCallback? onRetry,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
    ),
    builder: (sheetContext) {
      final maxHeight = ResponsiveValue.heightFraction(
        sheetContext,
        0.88,
        max: MediaQuery.sizeOf(sheetContext).height -
            MevoraSafeAreaInsets.top(sheetContext),
      );
      final compact = sheetContext.isCompactHeight ||
          sheetContext.isVeryCompactHeight;

      return Padding(
        padding: MevoraSafeAreaInsets.sheetOuterPadding(sheetContext),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              sheetContext.responsiveGutter,
              AppSpacing.sm,
              sheetContext.responsiveGutter,
              AppSpacing.lg,
            ),
            child: WhyYouMatchedReasonsPanel(
              status: status,
              result: result,
              reasons: reasons,
              message: message,
              onRetry: onRetry == null
                  ? null
                  : () {
                      unawaited(Navigator.of(sheetContext).maybePop());
                      onRetry();
                    },
              compact: compact,
            ),
          ),
        ),
      );
    },
  );
}
