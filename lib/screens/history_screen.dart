import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../app_state.dart';
import '../models/routine.dart';
import '../services/share_service.dart';
import '../theme.dart';
import 'certify_screen.dart';
import 'retro_screen.dart';

class HistoryBody extends StatefulWidget {
  final AppState state;
  const HistoryBody({super.key, required this.state});

  @override
  State<HistoryBody> createState() => _HistoryBodyState();
}

class _HistoryBodyState extends State<HistoryBody> {
  String? _selectedRoutineId;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final state = widget.state;
        final certs = state.allCertsSorted();
        if (state.routines.isEmpty && certs.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('아직 인증 기록이 없어요.\n첫 도장을 찍으면 여기에 추억으로 쌓입니다.',
                  textAlign: TextAlign.center),
            ),
          );
        }

        final routine = state.routineById(
                _selectedRoutineId ?? state.routines.firstOrNull?.id ?? '') ??
            state.routines.firstOrNull;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (routine != null) ...[
              // 루틴 선택 칩
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: state.routines.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) {
                    final r = state.routines[i];
                    return ChoiceChip(
                      label: Text(r.title,
                          style: const TextStyle(fontSize: 12)),
                      selected: r.id == routine.id,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) =>
                          setState(() => _selectedRoutineId = r.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _StampCalendar(state: state, routine: routine),
              const SizedBox(height: 24),
            ],
            if (certs.isNotEmpty) ...[
              Text('전체 앨범', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
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
              ),
            ],
          ],
        );
      },
    );
  }
}

/// ── 도장 달력 — 시즌 전체를 한눈에, 인증한 날엔 도장 ──
class _StampCalendar extends StatelessWidget {
  final AppState state;
  final Routine routine;
  const _StampCalendar({required this.state, required this.routine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final percent = state.progressPercent(routine.id);
    final done = state.certifiedDayCount(routine.id);
    final total = routine.totalDutyDays();
    final daysLeft = routine.daysLeft(today);

    // 주 단위 셀 목록 (월요일 시작으로 정렬)
    final days = <DateTime>[];
    var cursor = routine.startDate
        .subtract(Duration(days: routine.startDate.weekday - 1));
    while (!cursor.isAfter(routine.endDate)) {
      days.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    // 마지막 주 채우기
    while (days.length % 7 != 0) {
      days.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    // 최장 연속 인증 (의무일 기준)
    var longest = 0;
    var cur = 0;
    for (var d = routine.startDate;
        !d.isAfter(todayOnly) && !d.isAfter(routine.endDate);
        d = d.add(const Duration(days: 1))) {
      if (!routine.isDutyDay(d)) continue;
      if (state.isCertified(routine.id, d)) {
        cur++;
        if (cur > longest) longest = cur;
      } else {
        cur = 0;
      }
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더: 루틴명(브랜드 블루) + 기간/D-day
            Text(routine.title,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(color: cs.primary, fontSize: 19),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(
              '${DateFormat('yy.MM.dd').format(routine.startDate)}'
              ' ~ ${DateFormat('yy.MM.dd').format(routine.endDate)}'
              '${daysLeft >= 0 ? ' · D-$daysLeft' : ' · 시즌 종료'}',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            // 통계 3타일 (Stitch: Completion / Longest / Stamps)
            Row(
              children: [
                _StatTile(label: '달성률', value: '$percent%'),
                const SizedBox(width: 8),
                _StatTile(label: '최장 연속', value: '$longest일'),
                const SizedBox(width: 8),
                _StatTile(
                    label: '도장',
                    value: '$done/$total',
                    highlight: true),
              ],
            ),
            const SizedBox(height: 14),
            // 요일 헤더
            Row(
              children: ['월', '화', '수', '목', '금', '토', '일']
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(d,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: cs.onSurfaceVariant)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 4),
            // 도장 그리드
            for (var w = 0; w < days.length ~/ 7; w++)
              Row(
                children: List.generate(7, (i) {
                  final d = days[w * 7 + i];
                  return Expanded(
                      child: _DayCell(
                    state: state,
                    routine: routine,
                    day: d,
                    today: todayOnly,
                  ));
                }),
              ),
            const SizedBox(height: 12),
            // 회고 카드 — 시즌이 끝났으면 강조, 진행 중이면 중간 회고
            SizedBox(
              width: double.infinity,
              child: daysLeft < 0
                  ? FilledButton.icon(
                      onPressed: () =>
                          openRetroCard(context, state, routine),
                      icon: const Icon(Icons.card_giftcard, size: 18),
                      label: const Text('시즌 회고 카드 보기'),
                    )
                  : OutlinedButton.icon(
                      onPressed: () =>
                          openRetroCard(context, state, routine),
                      icon: const Icon(Icons.insights_outlined, size: 18),
                      label: const Text('중간 회고 카드'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 통계 타일 — 도장 타일은 인주색 테두리 강조
class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _StatTile(
      {required this.label, required this.value, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: highlight ? AppTheme.stampSoft.withValues(alpha: 0.5) : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: highlight ? AppTheme.stamp : cs.outlineVariant,
              width: highlight ? 1.4 : 1),
        ),
        child: Column(
          children: [
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            const SizedBox(height: 3),
            Text(value,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: highlight ? AppTheme.stamp : cs.primary,
                )),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final AppState state;
  final Routine routine;
  final DateTime day;
  final DateTime today;
  const _DayCell(
      {required this.state,
      required this.routine,
      required this.day,
      required this.today});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final inSeason =
        !day.isBefore(routine.startDate) && !day.isAfter(routine.endDate);
    final isDuty = routine.isDutyDay(day);
    final certified = inSeason && state.isCertified(routine.id, day);
    final isToday = day == today;
    final isPast = day.isBefore(today);
    final missed = inSeason && isDuty && isPast && !certified;

    Certification? cert;
    if (certified) {
      final key = dateKeyOf(day);
      for (final c in state.certsForRoutine(routine.id)) {
        if (c.dateKey == key) {
          cert = c;
          break;
        }
      }
    }

    // Stitch 시안: 인증 = 인주색 둥근 사각 도장, 남은 날 = 옅은 테두리 + 날짜
    return AspectRatio(
      aspectRatio: 1,
      child: InkWell(
        onTap: cert != null
            ? () => showCertDetail(context, cert!, routine)
            : (missed ? () => _offerRecovery(context) : null),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: certified
                ? AppTheme.stampSoft.withValues(alpha: 0.6)
                : missed
                    ? cs.errorContainer.withValues(alpha: 0.4)
                    : Colors.transparent,
            border: certified
                ? Border.all(color: AppTheme.stamp, width: 1.6)
                : isToday
                    ? Border.all(color: cs.primary, width: 1.5)
                    : inSeason && isDuty
                        ? Border.all(
                            color: cs.outlineVariant
                                .withValues(alpha: 0.6))
                        : null,
          ),
          alignment: Alignment.center,
          child: certified
              ? Transform.rotate(
                  angle: -0.12,
                  child: const Icon(Icons.check_circle_outline,
                      size: 17, color: AppTheme.stamp),
                )
              : Text(
                  inSeason ? '${day.day}' : '',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: !isDuty
                        ? cs.outlineVariant
                        : isPast || isToday
                            ? cs.onSurfaceVariant
                            : cs.outlineVariant,
                    fontWeight:
                        isToday ? FontWeight.w800 : FontWeight.w400,
                  ),
                ),
        ),
      ),
    );
  }

  /// 놓친 지난 날짜 탭 → 누락 인증 복구 (그날 사진/URL로 소급 인증)
  void _offerRecovery(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${DateFormat('M월 d일 (E)', 'ko').format(day)} 인증 복구',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '이 날 인증을 놓쳤거나 기록이 사라졌나요?\n그날 찍은 사진(날짜 워터마크)으로 도장을 되살릴 수 있어요.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('이 날 인증 복구하기'),
              onTap: () {
                Navigator.pop(sheetCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CertifyScreen(
                      state: state,
                      routine: routine,
                      day: day,
                      recovery: true,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// 인증 상세 — 사진·검증 내용·메모·공유 (도장 달력/앨범 공용)
void showCertDetail(
    BuildContext context, Certification cert, Routine? routine) {
  showDialog(
    context: context,
    builder: (_) => _CertDetailDialog(cert: cert, routine: routine),
  );
}

class _CertDetailDialog extends StatefulWidget {
  final Certification cert;
  final Routine? routine;
  const _CertDetailDialog({required this.cert, required this.routine});

  @override
  State<_CertDetailDialog> createState() => _CertDetailDialogState();
}

class _CertDetailDialogState extends State<_CertDetailDialog> {
  final _player = AudioPlayer();
  bool _playing = false;
  VideoPlayerController? _videoCtrl;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
    final vp = widget.cert.videoPath;
    if (vp != null && File(vp).existsSync()) {
      _videoCtrl = VideoPlayerController.file(File(vp))
        ..initialize().then((_) {
          if (mounted) setState(() {});
        });
    }
  }

  @override
  void dispose() {
    _player.dispose();
    _videoCtrl?.dispose();
    super.dispose();
  }

  String _fmtDuration(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return m > 0 ? '$m분 $s초' : '$s초';
  }

  @override
  Widget build(BuildContext context) {
    final cert = widget.cert;
    final routine = widget.routine;
    final cs = Theme.of(context).colorScheme;
    final method = cert.verifyMethod;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (cert.hasPhoto && File(cert.photoPath).existsSync())
              Image.file(File(cert.photoPath)),
            // 동영상 인증 재생
            if (_videoCtrl != null && _videoCtrl!.value.isInitialized)
              AspectRatio(
                aspectRatio: _videoCtrl!.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_videoCtrl!),
                    IconButton.filled(
                      onPressed: () => setState(() {
                        _videoCtrl!.value.isPlaying
                            ? _videoCtrl!.pause()
                            : _videoCtrl!.play();
                      }),
                      icon: Icon(_videoCtrl!.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const StampMark(size: 34, filledCheck: true),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(routine?.title ?? '(삭제된 루틴)',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium),
                            Text(
                              DateFormat('yyyy년 M월 d일 HH:mm 인증')
                                  .format(cert.timestamp),
                              style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 검증 내용
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          switch (method) {
                            'timer' => '⏱ 타이머 인증'
                                '${cert.durationSec != null ? ' · ${_fmtDuration(cert.durationSec!)} 수행' : ''}',
                            'audio' => '🎙 녹음 인증',
                            'video' => '🎬 동영상 인증',
                            'steps' =>
                              '👟 걸음수 인증${cert.steps != null ? ' · ${cert.steps}보 확인' : ''}',
                            'link' => '🔗 URL 인증',
                            _ => '📷 사진 인증 (날짜 워터마크)',
                          },
                          style:
                              const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (method == 'link' &&
                            cert.linkUrl != null &&
                            cert.linkUrl!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () => launchUrl(
                              Uri.parse(cert.linkUrl!),
                              mode: LaunchMode.externalApplication,
                            ),
                            child: Text(
                              cert.linkUrl!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: cs.primary,
                                decoration: TextDecoration.underline,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (method == 'audio' &&
                            cert.audioPath != null &&
                            File(cert.audioPath!).existsSync()) ...[
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              if (_playing) {
                                await _player.stop();
                                setState(() => _playing = false);
                              } else {
                                await _player.play(
                                    DeviceFileSource(cert.audioPath!));
                                setState(() => _playing = true);
                              }
                            },
                            icon: Icon(
                                _playing ? Icons.stop : Icons.play_arrow),
                            label: Text(_playing ? '정지' : '녹음 듣기'),
                          ),
                        ],
                      ],
                    ),
                  ),
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

class _CertTile extends StatelessWidget {
  final Certification cert;
  final Routine? routine;
  const _CertTile({required this.cert, required this.routine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final file = File(cert.photoPath);
    final hasPhoto = cert.hasPhoto && file.existsSync();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showCertDetail(context, cert, routine),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: hasPhoto
                  ? Image.file(file, fit: BoxFit.cover)
                  : Container(
                      color: cs.surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          cert.verifyMethod == 'timer'
                              ? Icons.timer_outlined
                              : cert.verifyMethod == 'audio'
                                  ? Icons.mic_rounded
                                  : cert.verifyMethod == 'video'
                                      ? Icons.videocam_rounded
                                      : cert.verifyMethod == 'link'
                                          ? Icons.link_rounded
                                          : cert.verifyMethod == 'steps'
                                          ? Icons.directions_walk_rounded
                                          : Icons.image_not_supported,
                          size: 36,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
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
}
