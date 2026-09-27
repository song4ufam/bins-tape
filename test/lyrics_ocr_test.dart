import 'package:bins_tape/lyrics_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

FrameText f(int ms, String t) => FrameText(Duration(milliseconds: ms), t);

void main() {
  test('같은 글자가 이어지면 한 줄이고, 처음 나타난 시각을 쓴다', () {
    final lines = buildLyricsFromFrames([
      f(0, ''),
      f(500, '빈 테이프를 돌리며'),
      f(1000, '빈 테이프를 돌리며'),
      f(1500, '빈 테이프를 돌리며'),
      f(2000, ''),
      f(2500, '오늘도 목소리를 채워봐'),
      f(3000, '오늘도 목소리를 채워봐'),
    ]);
    expect(lines.length, 2);
    expect(lines[0].time, const Duration(milliseconds: 500));
    expect(lines[0].text, '빈 테이프를 돌리며');
    expect(lines[1].time, const Duration(milliseconds: 2500));
  });

  test('OCR 오타가 조금 있어도 같은 줄로 묶고 가장 긴 글자를 쓴다', () {
    final lines = buildLyricsFromFrames([
      f(0, '아무도 몰라도'),
      f(500, '아무도 몰라도 괜찮아'),
      f(1000, '아무도 몰라도 괜찮아'),
      f(1500, '아무도 몰리도 괜찮아'),
    ]);
    expect(lines.length, 1);
    expect(lines.single.text, '아무도 몰라도 괜찮아');
    expect(lines.single.time, Duration.zero);
  });

  test('한 프레임만 보였다 사라지는 잡음은 버린다', () {
    final lines = buildLyricsFromFrames([
      f(0, ''),
      f(500, 'LOGO'),
      f(1000, ''),
      f(1500, '진짜 가사예요'),
      f(2000, '진짜 가사예요'),
    ]);
    expect(lines.map((l) => l.text), ['진짜 가사예요']);
  });

  test('잠깐 끊겼다가 같은 글자가 다시 나오면 한 줄로 합친다', () {
    final lines = buildLyricsFromFrames([
      f(0, '언젠가 세상에 들려줄'),
      f(500, '언젠가 세상에 들려줄'),
      f(1000, ''),
      f(1500, '언젠가 세상에 들려줄'),
      f(2000, '언젠가 세상에 들려줄'),
      f(2500, ''),
      f(3000, ''),
      f(3500, ''),
      f(4000, ''),
      f(4500, '그 날을 위해'),
      f(5000, '그 날을 위해'),
    ]);
    expect(lines.length, 2);
    expect(lines[0].time, Duration.zero);
    expect(lines[1].text, '그 날을 위해');
  });

  test('서로 다른 글자는 유사도가 낮다', () {
    expect(textSimilarity('사랑이 떠나가요', '너 없는 지금도'), lessThan(0.5));
    expect(textSimilarity('Bin\'s Tape', "bins tape!"), 1);
  });

  test('프레임이 비어 있으면 빈 목록', () {
    expect(buildLyricsFromFrames([]), isEmpty);
  });
}
