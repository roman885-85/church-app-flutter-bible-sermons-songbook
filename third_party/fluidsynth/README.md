# FluidSynth для мінусів пісенника

Застосунок грає MIDI пісень власним синтезатором — **FluidSynth 2.6.0** (lib/midi/), зі
звуковими банками сайту (`/uploads/soundfonts/*.sf3`, див. `tools/soundfont/README.md`).
Звук пишеться у WAV швидше, ніж звучить, і грає через just_audio: у фоні, з кнопками
в сповіщенні, без інтернету (після першого завантаження звучання й файла пісні).

## Звідки бібліотеки

`android/app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64}/`:

| Файл | Звідки | Ліцензія |
|---|---|---|
| libfluidsynth.so | офіційний реліз FluidSynth v2.6.0, `fluidsynth-v2.6.0-android24.zip` (github.com/FluidSynth/fluidsynth/releases, SHA-256 `81cd70dddb3381cda02c430a6657923766d1acb83de11d266d7a19aee3c7ca4d`) | LGPL-2.1 |
| libsndfile.so | той самий архів (читає SF3 — стиснені Vorbis семпли) | LGPL-2.1 |
| libogg.so, libvorbis.so, libvorbisenc.so, libFLAC.so, libopus.so | той самий архів (залежності libsndfile) | BSD |
| liboboe.so | той самий архів (залежність libfluidsynth; звук у застосунку через неї не йде) | Apache-2.0 |
| libc++_shared.so | Android NDK 28.2.13676358 (`sysroot/usr/lib/<abi>/`) | Apache-2.0 з винятком LLVM |

Усі файли пройшли `llvm-strip --strip-unneeded` (без налагоджувальних символів: 2,8–4 МБ на
ABI замість 14). Вирівнювання сегментів — 16 КБ (0x4000), тож вантажаться й на пристроях
із 16-КБ сторінками пам'яті. `libfluidsynth-assetloader.so` і `libvorbisfile.so` з архіву не
потрібні й не покладені.

LGPL: бібліотеки FluidSynth і libsndfile підключаються динамічно й лежать у APK окремими
файлами — їх можна замінити своєю збіркою. Вихідний код — у репозиторіях проєктів
(github.com/FluidSynth/fluidsynth, github.com/libsndfile/libsndfile). Підпис під програвачем
мінусу називає синтезатор і ліцензію.

x86_64 потрібен лише емулятору: у збірку з `--target-platform` без `android-x64`
(звичайний реліз для телефонів) він не пакується — див. `packaging` в
`android/app/build.gradle.kts`.

## Як оновити

1. Завантажити `fluidsynth-vX.Y.Z-android24.zip` з релізів FluidSynth, звірити SHA-256.
2. Для кожного ABI: `llvm-strip --strip-unneeded -o jniLibs/<abi>/<lib>.so <zip>/lib/<abi>/<lib>.so`
   для libfluidsynth, libsndfile, libogg, libvorbis, libvorbisenc, libFLAC, libopus, liboboe.
   Перевірити `llvm-readelf -d libfluidsynth.so | grep NEEDED` — чи не з'явилось нових залежностей.
3. `libc++_shared.so` — з NDK тієї версії, що в `~/Library/Android/sdk/ndk/`, теж через strip.
4. Перевірити на емуляторі (збірка з `android-x64`): мінус грає, `adb logcat | grep midi-synth`
   показує час рендеру й пік.

## Як це працює (lib/midi/)

- `fluidsynth.dart` — прив'язка dart:ffi до C API.
- `midi_file.dart` — розбір MIDI у Dart: тривалість за темпами, слова караоке (CP1251), програми каналів.
- `renderer.dart` — окремий isolate з FluidSynth: `player.timing-source=sample`, власний колбек
  подій (вимкнені партії, інструмент слухача, транспонування), рендер блоками у WAV-файл `.part`,
  обмежувач піків, перейменування в `.wav`, коли готово.
- `midi_audio_source.dart` — `StreamAudioSource`: програвач читає файл, поки той дописується.
- `services/midi.dart` — звучання (завантаження банку), файл пісні, вибір слухача, перезапуск
  з того самого місця після зміни тональності/темпу/партій, кеш двох останніх рендерів.
