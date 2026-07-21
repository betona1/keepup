import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/retro_stats.dart';
import 'share_service.dart';

/// 회고 카드를 이미지로 굽고 OS 공유 시트로 내보낸다.
/// (사용자가 카톡 오픈채팅방 등 대상을 직접 고른다 — 기획서 3.3)
class RetroService {
  /// 화면에 붙어 있는 [boundaryKey]의 위젯을 PNG로 캡처해 파일로 저장한다.
  static Future<File> capture(
    GlobalKey boundaryKey, {
    double pixelRatio = 3.0,
  }) async {
    final ctx = boundaryKey.currentContext;
    if (ctx == null) {
      throw StateError('회고 카드가 아직 화면에 그려지지 않았어요');
    }
    final boundary = ctx.findRenderObject() as RenderRepaintBoundary;

    // 첫 프레임에 아직 페인트되지 않았으면 다음 프레임을 기다린다
    if (boundary.debugNeedsPaint) {
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }

    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) throw StateError('카드 이미지를 만들지 못했어요');

    final dir = await getApplicationDocumentsDirectory();
    final retroDir = Directory('${dir.path}/retro');
    if (!await retroDir.exists()) await retroDir.create(recursive: true);

    final path =
        '${retroDir.path}/retro_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File(path);
    await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    return file;
  }

  /// 회고 카드를 캡처해 공유 시트를 띄운다.
  static Future<void> share(GlobalKey boundaryKey, RetroStats stats) async {
    final file = await capture(boundaryKey);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        text: _caption(stats),
      ),
    );
  }

  static String _caption(RetroStats stats) {
    final r = stats.routine;
    final f = DateFormat('yyyy.MM.dd');
    final b = StringBuffer()
      ..writeln('[${r.title}] ${stats.ended ? '시즌 완료' : '중간 회고'} 🏁')
      ..writeln('${f.format(r.startDate)} ~ ${f.format(r.endDate)}'
          ' (${stats.seasonDays}일)')
      ..writeln(
          '달성률 ${stats.percent}% · 도장 ${stats.certifiedDays}/${stats.totalDutyDays}일'
          ' · 최장 연속 ${stats.longestStreak}일');
    final tally = stats.tallyLabel;
    if (tally != null) b.writeln(tally);
    b.write('———\n📱 습관 인증 챌린지 앱 「Log Challenge」 👉 ${ShareService.appLink}');
    return b.toString();
  }
}
