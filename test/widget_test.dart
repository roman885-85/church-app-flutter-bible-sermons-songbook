import 'package:church/api/models.dart';
import 'package:church/util/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('розбір глави з аудіо: вірш за часом', () {
    final chapter = BibleChapter.fromJson({
      'translation': 'cuv23',
      'bookNr': 43,
      'bookName': 'Івана',
      'chapter': 3,
      'verses': [
        {'verse': 1, 'text': 'a', 'plain': 'a'},
        {'verse': 2, 'text': 'b', 'plain': 'b'},
      ],
      'audio': [
        {
          'setCode': 'ukr-audio',
          'title': 'Аудіо',
          'narrator': 'читає',
          'url': 'https://baptist.com.ua/a.mp3',
          'durationSec': 60,
          'verseStarts': [
            {'verse': 1, 'start': 10},
            {'verse': 2, 'start': 20.5},
          ],
        },
      ],
      'next': {'bookNr': 43, 'chapter': 4},
    });
    final audio = chapter.audio.single;
    expect(audio.verseAt(const Duration(seconds: 5)), isNull);
    expect(audio.verseAt(const Duration(seconds: 12)), 1);
    expect(audio.verseAt(const Duration(seconds: 21)), 2);
    expect(chapter.next?.chapter, 4);
  });

  test('проповідь без поля не падає', () {
    final s = Sermon.fromJson({'id': '7', 'title': 'Назва', 'audioUrl': 'https://x/y.mp3'});
    expect(s.id, 7);
    expect(s.preacher, '');
    expect(Sermon.fromJson(s.toJson()).audioUrl, s.audioUrl);
  });

  test('тривалість і годинник', () {
    expect(humanDuration(42 * 60), '42 хв');
    expect(humanDuration(65 * 60), '1 год 05 хв');
    expect(clock(const Duration(minutes: 62, seconds: 9)), '1:02:09');
  });
}
