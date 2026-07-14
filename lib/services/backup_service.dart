import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/routine.dart';

/// 기기 간 백업/이전 — 서버 없이 ZIP 파일 하나로 내보내고 불러온다.
/// ZIP 구성: data.json(루틴+인증, 미디어는 파일명만) + media/<파일들>
class BackupService {
  static String _basename(String path) => path.split('/').last;

  /// 모든 데이터를 ZIP으로 만들어 공유 시트로 내보낸다 (카톡 나에게 보내기, 드라이브 등)
  static Future<int> exportAndShare(
      List<Routine> routines, List<Certification> certs) async {
    final archive = Archive();

    // 미디어 수집 (사진/녹음/영상 — 존재하는 파일만)
    final mediaPaths = <String>{};
    for (final c in certs) {
      for (final p in [c.photoPath, c.audioPath ?? '', c.videoPath ?? '']) {
        if (p.isNotEmpty && File(p).existsSync()) mediaPaths.add(p);
      }
    }
    for (final p in mediaPaths) {
      final bytes = await File(p).readAsBytes();
      archive.addFile(
          ArchiveFile('media/${_basename(p)}', bytes.length, bytes));
    }

    // 데이터 — 경로는 파일명만 남긴다 (기기마다 절대경로가 달라서)
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'routines': routines.map((r) => r.toJson()).toList(),
      'certs': certs.map((c) {
        final j = c.toJson();
        j['photoPath'] = c.photoPath.isEmpty ? '' : _basename(c.photoPath);
        j['audioPath'] =
            c.audioPath == null ? null : _basename(c.audioPath!);
        j['videoPath'] =
            c.videoPath == null ? null : _basename(c.videoPath!);
        return j;
      }).toList(),
    };
    final jsonBytes = utf8.encode(jsonEncode(data));
    archive.addFile(ArchiveFile('data.json', jsonBytes.length, jsonBytes));

    final zipBytes = ZipEncoder().encode(archive);
    final tmp = await getTemporaryDirectory();
    final name =
        'keepup_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.zip';
    final zipFile = File('${tmp.path}/$name');
    await zipFile.writeAsBytes(zipBytes);

    await SharePlus.instance.share(ShareParams(
      files: [XFile(zipFile.path)],
      text: 'KeepUp 백업 (${routines.length}개 루틴, ${certs.length}개 인증)',
    ));
    return mediaPaths.length;
  }

  /// 백업 ZIP을 선택해 읽는다. 취소하면 null.
  static Future<(List<Routine>, List<Certification>)?> pickAndRead() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path == null) return null;

    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    final dataEntry = archive.findFile('data.json');
    if (dataEntry == null) {
      throw const FormatException('KeepUp 백업 파일이 아닙니다 (data.json 없음)');
    }
    final data = jsonDecode(utf8.decode(dataEntry.content as List<int>))
        as Map<String, dynamic>;

    // 미디어 복원 → 앱 문서 폴더
    final docs = await getApplicationDocumentsDirectory();
    for (final f in archive.files) {
      if (f.isFile && f.name.startsWith('media/')) {
        final out = File('${docs.path}/${f.name.substring(6)}');
        await out.writeAsBytes(f.content as List<int>);
      }
    }

    String fullOrEmpty(dynamic name) =>
        (name == null || (name as String).isEmpty) ? '' : '${docs.path}/$name';
    String? fullOrNull(dynamic name) =>
        (name == null || (name as String).isEmpty) ? null : '${docs.path}/$name';

    final routines = (data['routines'] as List)
        .map((e) => Routine.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final certs = (data['certs'] as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      m['photoPath'] = fullOrEmpty(m['photoPath']);
      m['audioPath'] = fullOrNull(m['audioPath']);
      m['videoPath'] = fullOrNull(m['videoPath']);
      return Certification.fromJson(m);
    }).toList();

    return (routines, certs);
  }
}
