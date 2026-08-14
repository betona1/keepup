import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import '../models/routine.dart';
import 'file_saver.dart';
import 'media_store.dart';

/// OS 기본 공유 시트로 인증을 공유한다.
/// (사용자가 직접 카카오톡 오픈채팅방 등 대상을 골라 전송 — 완전 합법)
class ShareService {
  /// 앱 다운로드(홍보) 링크 — 공유할 때마다 자연스럽게 붙어 앱이 알려진다.
  /// 2026-08-14 Play 출시 → 스토어 설치 링크로 교체 (탭하면 바로 설치 페이지).
  static const appLink =
      'https://play.google.com/store/apps/details?id=com.keywordream.keepup';

  /// 인증 문구 끝에 붙는 홍보 서명
  static String get _promoFooter =>
      '\n———\n📱 습관 인증 챌린지 앱 「로그챌린지」\n나도 습관도장 찍으러 가기 👉 $appLink';

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
    buffer.write(_promoFooter);
    final text = buffer.toString().trim();

    if (MediaStore.isWeb) {
      final bytes = await MediaStore.readBytes(cert.photoPath);
      await shareBytes(
        bytes: bytes,
        filename: 'logchallenge_${cert.timestamp.millisecondsSinceEpoch}.jpg',
        mimeType: 'image/jpeg',
        text: text,
      );
      return;
    }

    final file = File(cert.photoPath);
    if (await file.exists()) {
      await SharePlus.instance.share(ShareParams(
        files: [XFile(cert.photoPath)],
        text: text,
      ));
    } else {
      await SharePlus.instance.share(ShareParams(text: text));
    }
  }

  /// 웹에서 이미지 + 문구를 공유한다.
  /// 브라우저 공유 시트(모바일 사파리·크롬)를 먼저 시도하고,
  /// 파일 공유를 지원하지 않는 환경(PC 브라우저 등)이면 이미지를 내려받게 한다.
  static Future<void> shareBytes({
    required Uint8List? bytes,
    required String filename,
    required String mimeType,
    required String text,
  }) async {
    if (bytes != null) {
      try {
        await SharePlus.instance.share(ShareParams(
          files: [
            XFile.fromData(bytes, name: filename, mimeType: mimeType),
          ],
          fileNameOverrides: [filename],
          text: text,
        ));
        return;
      } catch (e) {
        debugPrint('브라우저 파일 공유 미지원 → 다운로드로 전환: $e');
      }
    }
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (e) {
      debugPrint('브라우저 문구 공유 실패(무시): $e');
    }
    if (bytes != null) {
      await downloadBytes(filename, bytes, mimeType);
    }
  }

  static String _fmtDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${two(d.month)}.${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }
}
