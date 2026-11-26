// StreamAudioSource у just_audio позначено «експериментальним» — він такий з 2021 р.
// і саме для цього призначений: звук, якого ще немає у файлі чи в мережі.
// ignore_for_file: experimental_member_use

import 'package:just_audio/just_audio.dart';

import 'renderer.dart';

/// Мінус, який синтезатор ще дописує, — для програвача це звичайний WAV:
/// усе готове віддається одразу, решта — щойно з'явиться. Тож грати можна
/// через кілька секунд після натиску, а фон, сповіщення й перемотування
/// працюють так само, як для проповідей.
class MidiAudioSource extends StreamAudioSource {
  MidiAudioSource(this.job, {super.tag});

  final MidiRenderJob job;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = start ?? 0;
    final to = (end ?? job.totalBytes).clamp(from, job.totalBytes);
    return StreamAudioResponse(
      sourceLength: job.totalBytes,
      contentLength: to - from,
      offset: from,
      stream: job.read(from, to),
      contentType: 'audio/wav',
    );
  }
}
