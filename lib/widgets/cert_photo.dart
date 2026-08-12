import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/media_store.dart';

/// 인증 사진 한 장 — 네이티브(파일)와 웹(브라우저 저장소)을 같은 방식으로 그린다.
///
/// 저장소가 즉시 이미지를 줄 수 있으면 곧바로 그리고(첫 프레임부터 깜빡임 없음),
/// 웹에서 아직 안 읽은 사진은 비동기로 읽어 온 뒤 그린다.
class CertPhoto extends StatefulWidget {
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// 사진이 없거나 유실됐을 때 대신 그릴 위젯
  final Widget? placeholder;

  const CertPhoto({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.placeholder,
  });

  @override
  State<CertPhoto> createState() => _CertPhotoState();
}

class _CertPhotoState extends State<CertPhoto> {
  ImageProvider? _provider;
  Future<Uint8List?>? _pending;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(CertPhoto old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _resolve();
  }

  void _resolve() {
    _provider = MediaStore.providerFor(widget.path);
    _pending = _provider == null && MediaStore.existsSync(widget.path)
        ? MediaStore.readBytes(widget.path)
        : null;
  }

  Widget _blank() =>
      widget.placeholder ?? SizedBox(width: widget.width, height: widget.height);

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    if (provider != null) {
      return Image(
        image: provider,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        errorBuilder: (_, __, ___) => _blank(),
      );
    }
    final pending = _pending;
    if (pending == null) return _blank();
    return FutureBuilder<Uint8List?>(
      future: pending,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return snap.connectionState == ConnectionState.done
              ? _blank()
              : SizedBox(width: widget.width, height: widget.height);
        }
        return Image.memory(
          bytes,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          errorBuilder: (_, __, ___) => _blank(),
        );
      },
    );
  }
}
