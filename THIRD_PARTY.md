# Сторонні компоненти / Third-party components

Код застосунку — MIT (файл `LICENSE`). Нижче — те, що лежить у репозиторії або підключається збіркою
й має власну ліцензію. / The app's own code is MIT (`LICENSE`). The following components keep their own licenses.

## Бібліотеки в готовому вигляді (`android/app/src/main/jniLibs/`)

| Бібліотека | Версія / джерело | Ліцензія |
|---|---|---|
| FluidSynth (`libfluidsynth.so`) | 2.6.0, офіційний випуск `fluidsynth-v2.6.0-android24.zip` | LGPL-2.1 |
| libsndfile (`libsndfile.so`) | з того самого архіву | LGPL-2.1 |
| libogg, libvorbis, libvorbisenc, libFLAC, libopus | з того самого архіву | BSD-3-Clause |
| Oboe (`liboboe.so`) | з того самого архіву | Apache-2.0 |
| LLVM libc++ (`libc++_shared.so`) | з Android NDK 28.2 | Apache-2.0 з винятком LLVM |

LGPL: FluidSynth і libsndfile підключаються **динамічно** й лежать окремими файлами — їх можна замінити своєю
збіркою (докладніше: `third_party/fluidsynth/README.md`). Вихідний код — у проєктах
[FluidSynth](https://github.com/FluidSynth/fluidsynth) і [libsndfile](https://github.com/libsndfile/libsndfile).
/ FluidSynth and libsndfile are linked dynamically and shipped as separate files; you can replace them with your own build.

## Пакети Dart / Flutter

Перелік і версії — `pubspec.yaml`, `pubspec.lock`. Усі — з pub.dev зі своїми ліцензіями (переважно BSD-3 і MIT);
застосунок показує їх повний список у «Меню → Застосунок → Ліцензії відкритого коду».
Шрифти сайту завантажує пакет `google_fonts` (OFL/Apache).

## Звукові банки (SoundFont)

У репозиторії їх немає: застосунок завантажує банки (`.sf3`) із сайту церкви під час першого прослуховування мінусу
й кешує на пристрої. Ліцензії банків — у каталозі сайту. / Sound banks are not part of this repository.
