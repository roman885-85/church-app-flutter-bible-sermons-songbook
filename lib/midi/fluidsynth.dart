import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Прив'язка до FluidSynth 2.6 (libfluidsynth.so з android/app/src/main/jniLibs).
///
/// Лише те, що потрібно синтезатору мінусів: синтезатор, звуковий банк,
/// програвач MIDI-файла з перехопленням подій і рендер у буфер.
/// Див. third_party/fluidsynth/README.md.
class FluidSynth {
  FluidSynth._(DynamicLibrary lib)
      : newSettings = lib.lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>('new_fluid_settings'),
        deleteSettings = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('delete_fluid_settings'),
        settingsSetNum = lib.lookupFunction<Int Function(Pointer<Void>, Pointer<Utf8>, Double), int Function(Pointer<Void>, Pointer<Utf8>, double)>(
            'fluid_settings_setnum'),
        settingsSetInt = lib.lookupFunction<Int Function(Pointer<Void>, Pointer<Utf8>, Int), int Function(Pointer<Void>, Pointer<Utf8>, int)>(
            'fluid_settings_setint'),
        settingsSetStr = lib.lookupFunction<Int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>), int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>)>(
            'fluid_settings_setstr'),
        newSynth = lib.lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('new_fluid_synth'),
        deleteSynth = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('delete_fluid_synth'),
        sfload = lib.lookupFunction<Int Function(Pointer<Void>, Pointer<Utf8>, Int), int Function(Pointer<Void>, Pointer<Utf8>, int)>('fluid_synth_sfload'),
        sfunload = lib.lookupFunction<Int Function(Pointer<Void>, Int, Int), int Function(Pointer<Void>, int, int)>('fluid_synth_sfunload'),
        systemReset = lib.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('fluid_synth_system_reset'),
        programChange = lib.lookupFunction<Int Function(Pointer<Void>, Int, Int), int Function(Pointer<Void>, int, int)>('fluid_synth_program_change'),
        noteOn = lib.lookupFunction<Int Function(Pointer<Void>, Int, Int, Int), int Function(Pointer<Void>, int, int, int)>('fluid_synth_noteon'),
        noteOff = lib.lookupFunction<Int Function(Pointer<Void>, Int, Int), int Function(Pointer<Void>, int, int)>('fluid_synth_noteoff'),
        handleMidiEvent =
            lib.lookupFunction<Int Function(Pointer<Void>, Pointer<Void>), int Function(Pointer<Void>, Pointer<Void>)>('fluid_synth_handle_midi_event'),
        writeFloat = lib.lookupFunction<Int Function(Pointer<Void>, Int, Pointer<Float>, Int, Int, Pointer<Float>, Int, Int),
            int Function(Pointer<Void>, int, Pointer<Float>, int, int, Pointer<Float>, int, int)>('fluid_synth_write_float'),
        activeVoices = lib.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('fluid_synth_get_active_voice_count'),
        newPlayer = lib.lookupFunction<Pointer<Void> Function(Pointer<Void>), Pointer<Void> Function(Pointer<Void>)>('new_fluid_player'),
        deletePlayer = lib.lookupFunction<Void Function(Pointer<Void>), void Function(Pointer<Void>)>('delete_fluid_player'),
        playerAddMem = lib.lookupFunction<Int Function(Pointer<Void>, Pointer<Uint8>, Size), int Function(Pointer<Void>, Pointer<Uint8>, int)>(
            'fluid_player_add_mem'),
        playerPlay = lib.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('fluid_player_play'),
        playerStop = lib.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('fluid_player_stop'),
        playerStatus = lib.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('fluid_player_get_status'),
        playerSetTempo = lib.lookupFunction<Int Function(Pointer<Void>, Int, Double), int Function(Pointer<Void>, int, double)>('fluid_player_set_tempo'),
        playerSetPlaybackCallback = lib.lookupFunction<
            Int Function(Pointer<Void>, Pointer<NativeFunction<MidiEventHandler>>, Pointer<Void>),
            int Function(Pointer<Void>, Pointer<NativeFunction<MidiEventHandler>>, Pointer<Void>)>('fluid_player_set_playback_callback'),
        eventType = lib.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('fluid_midi_event_get_type'),
        eventChannel = lib.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('fluid_midi_event_get_channel'),
        eventKey = lib.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('fluid_midi_event_get_key'),
        eventVelocity = lib.lookupFunction<Int Function(Pointer<Void>), int Function(Pointer<Void>)>('fluid_midi_event_get_velocity'),
        setLogFunction = lib.lookupFunction<Pointer<Void> Function(Int, Pointer<Void>, Pointer<Void>), Pointer<Void> Function(int, Pointer<Void>, Pointer<Void>)>(
            'fluid_set_log_function');

  static FluidSynth? _instance;

  /// Бібліотека завантажується один раз на isolate.
  static FluidSynth open() => _instance ??= FluidSynth._(DynamicLibrary.open('libfluidsynth.so'));

  static const ok = 0;
  static const failed = -1;
  static const playerPlaying = 1;
  static const tempoInternal = 0;
  static const logInfo = 3;
  static const logDebug = 4;

  final Pointer<Void> Function() newSettings;
  final void Function(Pointer<Void>) deleteSettings;
  final int Function(Pointer<Void>, Pointer<Utf8>, double) settingsSetNum;
  final int Function(Pointer<Void>, Pointer<Utf8>, int) settingsSetInt;
  final int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Utf8>) settingsSetStr;
  final Pointer<Void> Function(Pointer<Void>) newSynth;
  final void Function(Pointer<Void>) deleteSynth;
  final int Function(Pointer<Void>, Pointer<Utf8>, int) sfload;
  final int Function(Pointer<Void>, int, int) sfunload;
  final int Function(Pointer<Void>) systemReset;
  final int Function(Pointer<Void>, int, int) programChange;
  final int Function(Pointer<Void>, int, int, int) noteOn;
  final int Function(Pointer<Void>, int, int) noteOff;
  final int Function(Pointer<Void>, Pointer<Void>) handleMidiEvent;
  final int Function(Pointer<Void>, int, Pointer<Float>, int, int, Pointer<Float>, int, int) writeFloat;
  final int Function(Pointer<Void>) activeVoices;
  final Pointer<Void> Function(Pointer<Void>) newPlayer;
  final void Function(Pointer<Void>) deletePlayer;
  final int Function(Pointer<Void>, Pointer<Uint8>, int) playerAddMem;
  final int Function(Pointer<Void>) playerPlay;
  final int Function(Pointer<Void>) playerStop;
  final int Function(Pointer<Void>) playerStatus;
  final int Function(Pointer<Void>, int, double) playerSetTempo;
  final int Function(Pointer<Void>, Pointer<NativeFunction<MidiEventHandler>>, Pointer<Void>) playerSetPlaybackCallback;
  final int Function(Pointer<Void>) eventType;
  final int Function(Pointer<Void>) eventChannel;
  final int Function(Pointer<Void>) eventKey;
  final int Function(Pointer<Void>) eventVelocity;
  final Pointer<Void> Function(int, Pointer<Void>, Pointer<Void>) setLogFunction;

  bool setNum(Pointer<Void> settings, String name, double value) => using((arena) => settingsSetNum(settings, name.toNativeUtf8(allocator: arena), value) == ok);
  bool setInt(Pointer<Void> settings, String name, int value) => using((arena) => settingsSetInt(settings, name.toNativeUtf8(allocator: arena), value) == ok);
  bool setStr(Pointer<Void> settings, String name, String value) =>
      using((arena) => settingsSetStr(settings, name.toNativeUtf8(allocator: arena), value.toNativeUtf8(allocator: arena)) == ok);
}

/// `int handle_midi_event_func_t(void *data, fluid_midi_event_t *event)`.
typedef MidiEventHandler = Int Function(Pointer<Void> data, Pointer<Void> event);
