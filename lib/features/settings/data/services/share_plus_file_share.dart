import 'dart:io';

import 'package:mevora/features/settings/domain/services/file_share_port.dart';
import 'package:share_plus/share_plus.dart';

/// Platform share sheet via share_plus.
///
/// Android routes this through a content provider, so the receiving app gets
/// a temporary grant to this one file. The app's private directory is never
/// exposed and no storage permission is required.
class SharePlusFileShare implements FileSharePort {
  const SharePlusFileShare();

  @override
  Future<FileShareOutcome> shareFile({
    required String path,
    required String mimeType,
    String? subject,
  }) async {
    if (!File(path).existsSync()) {
      throw FileSystemException('Export file is missing', path);
    }
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType)],
        fileNameOverrides: [path.split(Platform.pathSeparator).last],
        subject: subject,
      ),
    );
    return switch (result.status) {
      ShareResultStatus.success => FileShareOutcome.shared,
      ShareResultStatus.dismissed => FileShareOutcome.dismissed,
      ShareResultStatus.unavailable => FileShareOutcome.unavailable,
    };
  }
}
