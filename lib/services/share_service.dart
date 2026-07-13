import 'dart:io';
import 'package:share_plus/share_plus.dart';
import '../models/routine.dart';

/// OS 기본 공유 시트로 인증을 공유한다.
/// (사용자가 직접 카카오톡 오픈채팅방 등 대상을 골라 전송 — 완전 합법)
class ShareService {
  static Future<void> shareCertification({
    required Certification cert,
    required Routine? routine,
  }) async {
    final title = routine?.title ?? '습관 인증';
    final buffer = StringBuffer();
    buffer.writeln('[$title] 인증 ✅');
    buffer.writeln(_fmtDate(cert.timestamp));
    if (cert.progressValue != null && cert.progressValue!.isNotEmpty) {
      buffer.writeln('진행: ${cert.progressValue}');
    }
    if (cert.isBackup) buffer.writeln('(백업 루틴)');
    if (cert.memo.isNotEmpty) buffer.writeln(cert.memo);

    final file = File(cert.photoPath);
    if (await file.exists()) {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(cert.photoPath)],
        text: buffer.toString().trim(),
      ));
    } else {
      await SharePlus.instance.share(ShareParams(text: buffer.toString().trim()));
    }
  }

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${two(d.month)}.${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
