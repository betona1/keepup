import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/routine.dart';
import 'file_saver.dart';
import 'media_store.dart';

/// 기기 간 백업/이전 — 서버 없이 ZIP 파일 하나로 내보내고 불러온다.
/// ZIP 구성: data.json(루틴+인증, 미디어는 파일명만) + media/<파일들>
///
/// 웹에서도 같은 형식을 쓰기 때문에, 폰 앱에서 만든 백업을 브라우저에서 열고
/// 그 반대로도 옮길 수 있다(앱 ↔ 웹 데이터 이사).
class BackupService {
  static String _basename(String path) =>
      path.split(RegExp(r'[/\\]')).last;

  /// 모든 데이터를 ZIP으로 만들어 내보낸다.
  /// 네이티브는 공유 시트(카톡 나에게 보내기·드라이브 등), 웹은 파일 다운로드.
  static Future<int> exportAndShare(
      List<Routine> routines, List<Certification> certs) async {
    final archive = Archive();

    // 미디어 수집 (사진/녹음/영상/루틴 아이콘 — 남아 있는 것만)
    final mediaPaths = <String>{};
    for (final c in certs) {
      for (final p in [c.photoPath, c.audioPath ?? '', c.videoPath ?? '']) {
        if (p.isNotEmpty && MediaStore.existsSync(p)) mediaPaths.add(p);
      }
    }
    for (final r in routines) {
      final p = r.iconPath;
      if (p != null && p.isNotEmpty && MediaStore.existsSync(p)) {
        mediaPaths.add(p);
      }
    }
    for (final p in mediaPaths) {
      final bytes = await MediaStore.readBytes(p);
      if (bytes == null) continue;
      archive.addFile(
          ArchiveFile('media/${_basename(p)}', bytes.length, bytes));
    }

    // 데이터 — 경로는 파일명만 남긴다 (기기마다 절대경로가 달라서)
    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'routines': routines.map((r) {
        final j = r.toJson();
        j['iconPath'] =
            r.iconPath == null ? null : _basename(r.iconPath!);
        return j;
      }).toList(),
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

    final zipBytes =
        Uint8List.fromList(ZipEncoder().encode(archive));
    final name =
        'keepup_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.zip';

    if (MediaStore.isWeb) {
      await downloadBytes(name, zipBytes, 'application/zip');
      return mediaPaths.length;
    }

    final tmp = await getTemporaryDirectory();
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
    final res = await FilePicker.platform
        .pickFiles(type: FileType.any, withData: MediaStore.isWeb);
    if (res == null || res.files.isEmpty) return null;
    final picked = res.files.first;

    // 웹은 바이트로, 네이티브는 경로로 돌아온다
    final Uint8List? raw = picked.bytes ??
        (picked.path == null ? null : await File(picked.path!).readAsBytes());
    if (raw == null) return null;

    final archive = ZipDecoder().decodeBytes(raw);
    final dataEntry = archive.findFile('data.json');
    if (dataEntry == null) {
      throw const FormatException('KeepUp 백업 파일이 아닙니다 (data.json 없음)');
    }
    final data = jsonDecode(utf8.decode(dataEntry.content as List<int>))
        as Map<String, dynamic>;

    // 미디어 복원 → 이 기기(또는 브라우저)의 저장소. 새 경로를 파일명으로 찾아 쓴다.
    final restored = <String, String>{};
    for (final f in archive.files) {
      if (!f.isFile || !f.name.startsWith('media/')) continue;
      final name = f.name.substring(6);
      if (name.isEmpty) continue;
      restored[name] = await MediaStore.saveBytes(
          name, Uint8List.fromList(f.content as List<int>));
    }

    String fullOrEmpty(dynamic name) =>
        (name == null || (name as String).isEmpty) ? '' : (restored[name] ?? '');
    String? fullOrNull(dynamic name) =>
        (name == null || (name as String).isEmpty) ? null : restored[name];

    final routines = (data['routines'] as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      m['iconPath'] = fullOrNull(m['iconPath']);
      return Routine.fromJson(m);
    }).toList();
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
