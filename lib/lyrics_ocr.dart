/// 영상 프레임에서 OCR로 읽은 글자를 "타임스탬프 붙은 가사"로 바꾸는 순수 로직.
/// 플랫폼(ML Kit 등)과 무관해서 테스트할 수 있다.

/// 영상 화면 중 글자를 읽을 세로 범위 (0=맨 위, 1=맨 아래).
/// 노래방/가사 영상은 가사가 자리한 곳만 읽어야 제목·워터마크가 안 섞인다.
class OcrRegion {
  final String label;
  final double top;
  final double bottom;
  const OcrRegion(this.label, this.top, this.bottom);
}

const ocrRegions = <OcrRegion>[
  OcrRegion('전체 화면', 0, 1),
  OcrRegion('아래쪽 절반', 0.5, 1),
  OcrRegion('가운데', 0.3, 0.7),
  OcrRegion('위쪽 절반', 0, 0.5),
];

/// 영상의 한 시점(프레임)에서 읽은 글자.
class FrameText {
  final Duration time;
  final String text;
  const FrameText(this.time, this.text);
}

class OcrLyricLine {
  final Duration time;
  final String text;
  const OcrLyricLine(this.time, this.text);
}

/// 공백/기호를 없애고 소문자로 맞춰서 OCR 오타·띄어쓰기 차이에 덜 민감하게 비교한다.
String normalizeOcrText(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '');

/// 0~1. 1이면 같은 글자.
double textSimilarity(String a, String b) {
  final x = normalizeOcrText(a);
  final y = normalizeOcrText(b);
  if (x.isEmpty && y.isEmpty) return 1;
  if (x.isEmpty || y.isEmpty) return 0;
  if (x == y) return 1;

  var prev = List<int>.generate(y.length + 1, (i) => i);
  for (var i = 1; i <= x.length; i++) {
    final cur = List<int>.filled(y.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= y.length; j++) {
      final cost = x.codeUnitAt(i - 1) == y.codeUnitAt(j - 1) ? 0 : 1;
      final del = prev[j] + 1;
      final ins = cur[j - 1] + 1;
      final sub = prev[j - 1] + cost;
      cur[j] = [del, ins, sub].reduce((m, v) => v < m ? v : m);
    }
    prev = cur;
  }
  final longest = x.length > y.length ? x.length : y.length;
  return 1 - prev[y.length] / longest;
}

/// 같은 가사 줄로 볼 수 있는지. 글자가 서서히 나타나는 자막은 앞부분만 먼저 보이므로
/// 한쪽이 다른 쪽의 앞부분이어도 같은 줄로 친다.
bool _sameLine(String a, String b, double threshold) {
  final x = normalizeOcrText(a);
  final y = normalizeOcrText(b);
  final shorter = x.length <= y.length ? x : y;
  final longer = x.length <= y.length ? y : x;
  if (shorter.length >= 2 && longer.startsWith(shorter)) return true;
  return textSimilarity(a, b) >= threshold;
}

class _Run {
  Duration start;
  Duration lastSeen;
  String best;
  int count = 1;
  _Run(this.start, this.best) : lastSeen = start;
}

/// 프레임별 글자를 가사 줄로 묶는다.
///
/// - 글자가 비어 있으면 줄이 끝난 것으로 본다.
/// - 이어지는 프레임의 글자가 (거의) 같으면 같은 줄로 보고, 처음 나타난 시각을 쓴다.
/// - 서서히 나타나는 자막은 가장 긴(=완성된) 글자를 쓴다.
/// - [minStableFrames] 프레임 이상 유지된 글자만 인정해서 깜빡이는 잡음을 버린다.
/// - 잠깐 끊겼다가 같은 글자가 다시 나오면 한 줄로 합친다.
List<OcrLyricLine> buildLyricsFromFrames(
  List<FrameText> frames, {
  double similarityThreshold = 0.75,
  int minStableFrames = 2,
  int maxGapFrames = 2,
}) {
  if (frames.isEmpty) return [];

  final runs = <_Run>[];
  _Run? current;
  for (final f in frames) {
    final text = f.text.trim();
    if (normalizeOcrText(text).length < 2) {
      current = null; // 글자 없음 → 줄 끝
      continue;
    }
    if (current != null && _sameLine(current.best, text, similarityThreshold)) {
      current.count++;
      current.lastSeen = f.time;
      if (normalizeOcrText(text).length > normalizeOcrText(current.best).length) {
        current.best = text;
      }
    } else {
      current = _Run(f.time, text);
      runs.add(current);
    }
  }

  final step = frames.length > 1
      ? frames[1].time - frames[0].time
      : const Duration(milliseconds: 500);
  final maxGap = step * (maxGapFrames + 1);

  // 잠깐 끊겨 둘로 쪼개진 같은 줄을 합친다.
  final merged = <_Run>[];
  for (final r in runs) {
    if (merged.isNotEmpty) {
      final last = merged.last;
      final gap = r.start - last.lastSeen;
      if (gap <= maxGap && _sameLine(last.best, r.best, similarityThreshold)) {
        last.count += r.count;
        last.lastSeen = r.lastSeen;
        if (normalizeOcrText(r.best).length > normalizeOcrText(last.best).length) {
          last.best = r.best;
        }
        continue;
      }
    }
    merged.add(r);
  }

  return [
    for (final r in merged)
      if (r.count >= minStableFrames) OcrLyricLine(r.start, r.best.trim()),
  ];
}
