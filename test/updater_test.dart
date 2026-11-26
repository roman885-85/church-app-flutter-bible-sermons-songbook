import 'package:flutter_test/flutter_test.dart';

import 'package:church/services/updater.dart';

/// Відповідь GitHub `releases/latest` — лише поля, які читає застосунок.
Map<String, dynamic> release({String tag = 'v1.0.15', List<Map<String, dynamic>>? assets, String body = 'Що нового'}) => {
      'tag_name': tag,
      'body': body,
      'published_at': '2026-11-27T10:00:00Z',
      'assets': assets ??
          [
            {
              'name': 'vidrodzhennia-1.0.15.apk',
              'state': 'uploaded',
              'size': 50000000,
              'digest': 'sha256:${'ab' * 32}',
              'browser_download_url': 'https://github.com/o/r/releases/download/v1.0.15/vidrodzhennia-1.0.15.apk',
            },
          ],
    };

void main() {
  group('версії', () {
    test('розбір тегів', () {
      expect(UpdateService.parseVersion('v1.0.15'), [1, 0, 15]);
      expect(UpdateService.parseVersion('app-v1.2.10'), [1, 2, 10]);
      expect(UpdateService.parseVersion('2.0.0+20000'), [2, 0, 0]);
      expect(UpdateService.parseVersion('nightly'), isNull);
    });

    test('порівняння числами, а не рядками', () {
      expect(UpdateService.compareVersions([1, 0, 12], [1, 0, 9]) > 0, isTrue);
      expect(UpdateService.compareVersions([1, 1, 0], [1, 0, 99]) > 0, isTrue);
      expect(UpdateService.compareVersions([1, 0, 14], [1, 0, 14]), 0);
    });
  });

  group('відповідь GitHub', () {
    test('новіший випуск пропонується з файлом, розміром і контрольною сумою', () {
      final info = UpdateService.parseGithubRelease(release(), '1.0.14')!;
      expect(info.version, '1.0.15');
      expect(info.notes, 'Що нового');
      expect(info.size, 50000000);
      expect(info.sha256, 'ab' * 32);
      expect(info.downloadUrl, startsWith('https://github.com/o/r/releases/download/v1.0.15/'));
      expect(info.publishedAt, DateTime.utc(2026, 11, 27, 10));
    });

    test('та сама або новіша версія на телефоні — оновлення немає', () {
      expect(UpdateService.parseVersion('1.0.15'), isNotNull);
      expect(UpdateService.parseGithubRelease(release(), '1.0.15'), isNull);
      expect(UpdateService.parseGithubRelease(release(), '1.1.0'), isNull);
    });

    test('без .apk у випуску — нічого пропонувати', () {
      final noApk = release(assets: [
        {'name': 'notes.txt', 'state': 'uploaded', 'browser_download_url': 'https://github.com/o/r/releases/download/v1.0.15/notes.txt'},
      ]);
      expect(UpdateService.parseGithubRelease(noApk, '1.0.14'), isNull);
    });

    test('файл ще вантажиться (state != uploaded) — пропускаємо', () {
      final starting = release(assets: [
        {'name': 'a.apk', 'state': 'starter', 'size': 1, 'browser_download_url': 'https://github.com/o/r/releases/download/v1.0.15/a.apk'},
      ]);
      expect(UpdateService.parseGithubRelease(starting, '1.0.14'), isNull);
    });

    test('посилання не https — не беремо', () {
      final http = release(assets: [
        {'name': 'a.apk', 'state': 'uploaded', 'size': 1, 'browser_download_url': 'http://example.com/a.apk'},
      ]);
      expect(UpdateService.parseGithubRelease(http, '1.0.14'), isNull);
    });

    test('сміття замість версії — помилка (тоді застосунок піде запасною дорогою через сайт)', () {
      expect(() => UpdateService.parseGithubRelease(release(tag: 'nightly'), '1.0.14'), throwsFormatException);
      expect(() => UpdateService.parseGithubRelease('не json-об\'єкт', '1.0.14'), throwsFormatException);
    });

    test('некоректна контрольна сума відкидається, а не ламає оновлення', () {
      final bad = release(assets: [
        {
          'name': 'a.apk',
          'state': 'uploaded',
          'size': 1,
          'digest': 'sha1:deadbeef',
          'browser_download_url': 'https://github.com/o/r/releases/download/v1.0.15/a.apk',
        },
      ]);
      expect(UpdateService.parseGithubRelease(bad, '1.0.14')!.sha256, isNull);
    });
  });
}
