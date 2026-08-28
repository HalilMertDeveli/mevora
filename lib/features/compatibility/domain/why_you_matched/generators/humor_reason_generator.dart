import 'package:mevora/features/compatibility/domain/why_you_matched/context/reason_generator_context.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_reason.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/generators/reason_generator.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/humor/humor_answer_comparator.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/humor/humor_reason_calculator.dart';

/// Humor Why You Matched reasons from real data only.
///
/// 1. Humor-tagged Q&A answers → "N of M similar choices" evidence
/// 2. Else Humor Lab vector → dimension / score evidence
///
/// Never invents. Never emits more than one humor reason per pair.
class HumorReasonGenerator extends ReasonGenerator {
  const HumorReasonGenerator();

  @override
  String get generatorId => 'humor';

  @override
  List<WhyYouMatchedReason> generate(ReasonGeneratorContext context) {
    final fromAnswers = _fromAnswers(context);
    if (fromAnswers != null) {
      return [fromAnswers];
    }

    final humor = context.humorCompatibility;
    if (humor == null) {
      return const [];
    }
    final fromLab = HumorReasonCalculator.fromHumorLab(
      candidateUid: context.candidate.uid,
      humor: humor,
    );
    return fromLab == null ? const [] : [fromLab];
  }

  WhyYouMatchedReason? _fromAnswers(ReasonGeneratorContext context) {
    final signals = context.humorAnswerSignals;
    if (!signals.hasAnyAnswers) {
      return null;
    }
    final comparison = HumorAnswerComparator.compare(
      viewerAnswers: signals.viewerAnswers,
      candidateAnswers: signals.candidateAnswers,
    );
    return HumorReasonCalculator.fromAnswers(
      candidateUid: context.candidate.uid,
      comparison: comparison,
    );
  }
}
