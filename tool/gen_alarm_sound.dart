// 알람음 생성기 — 앱에 내장할 '삐-삐-삐' 알람 사운드를 만든다.
//   dart run tool/gen_alarm_sound.dart
//
// 왜 직접 만드나: 기기 기본 알림음이 '없음'으로 설정돼 있으면 알림이 무음으로 뜬다.
// 앱이 자기 소리를 들고 있으면 그런 환경에서도 확실히 울린다.
//
// 출력: android/app/src/main/res/raw/alarm_beep.wav (22050Hz, mono, 16bit PCM)
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

const sampleRate = 22050;
const outPath = 'android/app/src/main/res/raw/alarm_beep.wav';

void main() {
  final samples = <int>[];

  // "삐 삐 삐 — (쉼)" 한 묶음을 3번 반복 = 약 3.2초.
  // 알림이 insistent 플래그로 반복 재생되므로 이 길이면 충분하다.
  for (var cycle = 0; cycle < 3; cycle++) {
    for (var beep = 0; beep < 3; beep++) {
      _tone(samples, freq: beep.isEven ? 880 : 1174, seconds: 0.17);
      _silence(samples, 0.10);
    }
    _silence(samples, 0.45);
  }

  final file = File(outPath);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(_wav(samples));
  final seconds = (samples.length / sampleRate).toStringAsFixed(2);
  stdout.writeln('· $outPath ($seconds초, ${file.lengthSync() ~/ 1024}KB)');
}

/// 사인파 한 톤. 앞뒤 8ms를 페이드해서 '틱' 하는 클릭 잡음을 없앤다.
void _tone(List<int> out, {required double freq, required double seconds}) {
  final n = (sampleRate * seconds).round();
  final fade = (sampleRate * 0.008).round();
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    // 기본음 + 3배음을 살짝 섞어 시끄럽고 잘 들리는 음색으로
    var v = math.sin(2 * math.pi * freq * t) * 0.78 +
        math.sin(2 * math.pi * freq * 3 * t) * 0.12;
    if (i < fade) v *= i / fade;
    if (i > n - fade) v *= (n - i) / fade;
    out.add((v * 32767 * 0.92).round().clamp(-32768, 32767));
  }
}

void _silence(List<int> out, double seconds) {
  out.addAll(List<int>.filled((sampleRate * seconds).round(), 0));
}

/// 16bit PCM mono WAV 파일 바이트 만들기
Uint8List _wav(List<int> samples) {
  final dataBytes = samples.length * 2;
  final b = BytesBuilder();

  void ascii(String s) => b.add(s.codeUnits);
  void u32(int v) => b.add(Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little));
  void u16(int v) => b.add(Uint8List(2)..buffer.asByteData().setUint16(0, v, Endian.little));

  ascii('RIFF');
  u32(36 + dataBytes);
  ascii('WAVE');
  ascii('fmt ');
  u32(16); // PCM 헤더 길이
  u16(1); // PCM
  u16(1); // 채널 1개
  u32(sampleRate);
  u32(sampleRate * 2); // 초당 바이트
  u16(2); // 블록 정렬
  u16(16); // 비트 깊이
  ascii('data');
  u32(dataBytes);

  final pcm = Uint8List(dataBytes);
  final view = pcm.buffer.asByteData();
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  b.add(pcm);
  return b.toBytes();
}
