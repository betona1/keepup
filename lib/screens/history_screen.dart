import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../app_state.dart';
import '../models/routine.dart';
import '../services/share_service.dart';

class HistoryBody extends StatelessWidget {
  final AppState state;
  const HistoryBody({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final certs = state.allCertsSorted();
        if (certs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('아직 인증 기록이 없어요.\n첫 인증을 남기면 여기에 추억으로 쌓입니다.',
                  textAlign: TextAlign.center),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.78,
          ),
          itemCount: certs.length,
          itemBuilder: (context, i) {
            final c = certs[i];
            final r = state.routineById(c.routineId);
            return _CertTile(cert: c, routine: r);
          },
        );
      },
    );
  }
}

class _CertTile extends StatelessWidget {
  final Certification cert;
  final Routine? routine;
  const _CertTile({required this.cert, required this.routine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final file = File(cert.photoPath);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetail(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: file.existsSync()
                  ? Image.file(file, fit: BoxFit.cover)
                  : Container(
                      color: cs.surfaceContainerHighest,
                      child: Icon(Icons.image_not_supported,
                          color: cs.onSurfaceVariant),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(routine?.title ?? '(삭제된 루틴)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(
                    DateFormat('yyyy.MM.dd HH:mm').format(cert.timestamp),
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (File(cert.photoPath).existsSync())
              Image.file(File(cert.photoPath)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(routine?.title ?? '(삭제된 루틴)',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(DateFormat('yyyy년 M월 d일 HH:mm 인증')
                      .format(cert.timestamp)),
                  if (cert.progressValue != null &&
                      cert.progressValue!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('진행: ${cert.progressValue}'),
                  ],
                  if (cert.isBackup) ...[
                    const SizedBox(height: 4),
                    const Text('백업 루틴으로 인증',
                        style: TextStyle(fontStyle: FontStyle.italic)),
                  ],
                  if (cert.memo.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(cert.memo),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.tonalIcon(
                      onPressed: () => ShareService.shareCertification(
                          cert: cert, routine: routine),
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('공유'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
