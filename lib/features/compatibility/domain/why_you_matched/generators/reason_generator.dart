import 'package:mevora/features/compatibility/domain/why_you_matched/context/reason_generator_context.dart';
import 'package:mevora/features/compatibility/domain/why_you_matched/entities/why_you_matched_reason.dart';

/// Produces zero or more verified reasons from one signal domain.
///
/// Returning an empty list means “insufficient or missing data” — never invent.
abstract class ReasonGenerator {
  const ReasonGenerator();

  String get generatorId;

  List<WhyYouMatchedReason> generate(ReasonGeneratorContext context);
}
