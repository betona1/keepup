import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';

import '../app_state.dart';
import '../models/routine.dart';
import '../services/media_store.dart';
import '../theme.dart';
import 'cert_photo.dart';

/// 루틴 카드 왼쪽의 아이콘 타일.
///
/// 기본은 검증 방식 아이콘(카메라·타이머 등)이고, 사용자가 사진을 골라
/// 정사각 썸네일로 꾸밀 수 있다. 탭하면 [showRoutineIconPicker]가 열린다.
class RoutineIconTile extends StatelessWidget {
  final Routine routine;
  final double size;
  final int level; // 도장 레벨 — 2단계부터는 기본 아이콘도 성장한 바브바브로
  final int variant; // 4·5단계 얼굴 변형 (0~3)
  const RoutineIconTile({
    super.key,
    required this.routine,
    this.size = 52,
    this.level = 1,
    this.variant = 0,
  });

  IconData get _methodIcon => switch (routine.verifyMethod) {
        VerifyMethod.photo => Icons.photo_camera_outlined,
        VerifyMethod.timer => Icons.timer_outlined,
        VerifyMethod.audio => Icons.mic_none_rounded,
        VerifyMethod.video => Icons.videocam_outlined,
        VerifyMethod.steps => Icons.directions_walk_rounded,
        VerifyMethod.link => Icons.link_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iconPath = routine.iconPath;
    final hasPhoto = iconPath != null && MediaStore.existsSync(iconPath);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              // 2단계부터 아이콘 테두리도 레벨 색으로 빛난다
              border: level >= 2
                  ? Border.all(
                      color: AppTheme.stampRingColors(level).last, width: 1.4)
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: hasPhoto
                ? CertPhoto(path: iconPath, fit: BoxFit.cover)
                : level >= 2
                    // 성장한 바브바브가 기본 아이콘이 된다
                    ? Center(
                        child: VaveFace(
                            size: size * 0.92, level: level, variant: variant))
                    : Icon(_methodIcon, color: cs.primary, size: size * 0.46),
          ),
          // 꾸밀 수 있다는 힌트 배지 (사진 아이콘)
          Positioned(
            right: -4,
            bottom: -4,
            child: Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLowest,
                shape: BoxShape.circle,
                border: Border.all(color: cs.outlineVariant, width: 1),
              ),
              child: Icon(
                hasPhoto ? Icons.edit : Icons.add_photo_alternate_outlined,
                size: size * 0.20,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 루틴 아이콘 썸네일 선택기 — 사진 출처를 고른 뒤 정사각 크롭 편집으로 이어진다.
Future<void> showRoutineIconPicker(
  BuildContext context,
  AppState state,
  Routine routine,
) async {
  final cs = Theme.of(context).colorScheme;

  // 이 루틴의 인증 사진 (최근 것부터, 남아 있는 것만)
  final certPhotos = state
      .certsForRoutine(routine.id)
      .where((c) => c.hasPhoto && MediaStore.existsSync(c.photoPath))
      .toList()
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text('루틴 아이콘 꾸미기',
                style: Theme.of(ctx)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontSize: 17)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('사진을 골라 확대·이동으로 원하는 부분만 잘라 넣어요.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
          ),
          // 최근 인증 사진 가로 스트립 — 바로 골라서 크롭으로
          if (certPhotos.isNotEmpty) ...[
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: certPhotos.length.clamp(0, 12),
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => InkWell(
                  onTap: () => Navigator.pop(ctx, 'cert:$i'),
                  borderRadius: BorderRadius.circular(12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CertPhoto(
                      path: certPhotos[i].photoPath,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          ListTile(
            leading: Icon(Icons.photo_library_outlined, color: cs.primary),
            title: const Text('갤러리에서 사진 고르기'),
            onTap: () => Navigator.pop(ctx, 'gallery'),
          ),
          if (routine.iconPath != null)
            ListTile(
              leading: Icon(Icons.restart_alt_rounded, color: cs.error),
              title: Text('기본 아이콘으로 되돌리기',
                  style: TextStyle(color: cs.error)),
              onTap: () => Navigator.pop(ctx, 'reset'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  if (choice == 'reset') {
    await state.updateRoutineIcon(routine.id, null);
    return;
  }

  // 원본 사진 바이트 확보
  Uint8List? bytes;
  if (choice == 'gallery') {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 92, maxWidth: 2000);
    if (x == null) return;
    bytes = await x.readAsBytes();
  } else if (choice.startsWith('cert:')) {
    final i = int.tryParse(choice.substring(5)) ?? 0;
    bytes = await MediaStore.readBytes(certPhotos[i].photoPath);
  }
  if (bytes == null || !context.mounted) return;

  // 정사각 크롭 편집 → 저장
  final cropped = await Navigator.push<Uint8List>(
    context,
    MaterialPageRoute(
        builder: (_) => IconCropScreen(bytes: bytes!), fullscreenDialog: true),
  );
  if (cropped == null || !context.mounted) return;

  final path = await MediaStore.saveBytes(
      'rticon_${routine.id}_${DateTime.now().millisecondsSinceEpoch}.png',
      cropped);
  await state.updateRoutineIcon(routine.id, path);
  if (context.mounted) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('루틴 아이콘을 바꿨어요 ✅')));
  }
}

/// 정사각 크롭 편집기 — 확대(핀치)·이동으로 원하는 부분을 정사각 창에 맞춘다.
class IconCropScreen extends StatefulWidget {
  final Uint8List bytes;
  const IconCropScreen({super.key, required this.bytes});

  @override
  State<IconCropScreen> createState() => _IconCropScreenState();
}

class _IconCropScreenState extends State<IconCropScreen> {
  final _boundaryKey = GlobalKey();
  final _viewCtrl = TransformationController();
  bool _saving = false;

  @override
  void dispose() {
    _viewCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(double viewportSize) async {
    setState(() => _saving = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      // 화면 크기와 무관하게 아이콘은 512px로 굽는다
      final image = await boundary.toImage(pixelRatio: 512 / viewportSize);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('이미지 캡처 실패');
      if (mounted) {
        Navigator.pop(context, data.buffer.asUint8List());
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('저장 실패: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final square =
        (MediaQuery.of(context).size.width - 48).clamp(200.0, 400.0);

    return Scaffold(
      appBar: AppBar(title: const Text('아이콘 자르기')),
      body: Column(
        children: [
          const Spacer(),
          Center(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.stamp, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
              clipBehavior: Clip.antiAlias,
              child: RepaintBoundary(
                key: _boundaryKey,
                child: SizedBox(
                  width: square,
                  height: square,
                  child: InteractiveViewer(
                    transformationController: _viewCtrl,
                    minScale: 1,
                    maxScale: 6,
                    child: Image.memory(
                      widget.bytes,
                      width: square,
                      height: square,
                      fit: BoxFit.cover, // 처음엔 꽉 채우고, 확대·이동으로 조절
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '두 손가락으로 확대하고, 끌어서 위치를 맞추세요.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _viewCtrl.value = Matrix4.identity(),
            icon: const Icon(Icons.center_focus_strong_outlined, size: 18),
            label: const Text('처음으로'),
          ),
          const Spacer(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : () => _save(square),
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check_rounded),
                      label: Text(_saving ? '저장 중…' : '이걸로 하기'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
