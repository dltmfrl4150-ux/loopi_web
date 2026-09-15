import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:video_player/video_player.dart';

import '../theme/loopi_colors.dart';
import '../utils/media_blob.dart';
import '../utils/media_download.dart';
import 'app_logo.dart';

/// Additive export helpers for the comparison UI.
///
/// Does not touch recording or comparison playback/sync logic.
class ComparisonExport {
  ComparisonExport._();

  static Future<void> showOptionsSheet({
    required BuildContext context,
    required GlobalKey snapshotKey,
    String? recordedMediaPath,
    VideoPlayerController? recordedController,
    String baseFileName = 'loopi_practice',
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '저장 / 내보내기',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 4),
                Text(
                  '원하는 방식으로 연습 결과를 저장해요.',
                  style: TextStyle(color: LoopiColors.textMuted(sheetContext)),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: const Text('내 영상만 저장'),
                  subtitle: const Text('녹화한 내 동작 영상을 다운로드해요'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(
                      _exportMyVideo(
                        context: context,
                        recordedMediaPath: recordedMediaPath,
                        recordedController: recordedController,
                        baseFileName: baseFileName,
                      ),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: const Text('비교 화면 저장'),
                  subtitle: const Text('나란히 보기 화면을 이미지로 저장해요'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    unawaited(
                      _exportComparisonSnapshot(
                        context: context,
                        snapshotKey: snapshotKey,
                        baseFileName: baseFileName,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  static Future<void> _exportMyVideo({
    required BuildContext context,
    String? recordedMediaPath,
    VideoPlayerController? recordedController,
    required String baseFileName,
  }) async {
    final path = (recordedMediaPath ?? recordedController?.dataSource)?.trim();
    if (path == null || path.isEmpty) {
      _snack(context, '저장할 내 영상을 찾지 못했어요. 녹화가 완료됐는지 확인해 주세요.');
      return;
    }

    // No client-side FFmpeg mux is configured. Show a watermarked preview UI,
    // then download the recorded blob as MP4.
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('내 영상 저장'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 9 / 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: Colors.black87,
                        child: recordedController != null &&
                                recordedController.value.isInitialized
                            ? FittedBox(
                                fit: BoxFit.cover,
                                child: SizedBox(
                                  width: recordedController.value.size.width,
                                  height: recordedController.value.size.height,
                                  child: VideoPlayer(recordedController),
                                ),
                              )
                            : const Center(
                                child: Icon(
                                  Icons.videocam,
                                  color: Colors.white54,
                                  size: 48,
                                ),
                              ),
                      ),
                      const Positioned(
                        right: 10,
                        bottom: 10,
                        child: Opacity(
                          opacity: 0.85,
                          child: AppLogo(height: 28),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '미리보기에 LOOPI 로고가 표시돼요. 다운로드되는 파일은 녹화본(MP4)이며, '
                '브라우저에서 바로 저장됩니다.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('다운로드'),
            ),
          ],
        );
      },
    );
    if (proceed != true || !context.mounted) return;

    final filename = '${_safeName(baseFileName)}_my_take.mp4';
    var ok = false;
    if (path.startsWith('blob:') ||
        path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('data:')) {
      final bytes = await readBlobUrlBytes(path);
      if (bytes != null && bytes.isNotEmpty) {
        ok = await downloadBytesAsFile(
          bytes: bytes,
          filename: filename,
          mimeType: 'video/mp4',
        );
      } else {
        ok = await downloadUrlAsFile(url: path, filename: filename);
      }
    } else if (kIsWeb) {
      _snack(context, '웹에서는 blob 경로의 영상만 바로 저장할 수 있어요.');
      return;
    } else {
      _snack(context, '이 플랫폼에서는 아직 파일 경로 다운로드를 지원하지 않아요.');
      return;
    }

    if (!context.mounted) return;
    _snack(
      context,
      ok ? '내 영상 다운로드를 시작했어요.' : '다운로드에 실패했어요. 다시 시도해 주세요.',
    );
  }

  /// TODO(export-comparison-video): Client-side mux of youtube_player_iframe +
  /// local MediaRecorder is not feasible without a backend or FFmpeg.wasm.
  /// Until then we export a high-quality image snapshot of the comparison UI.
  static Future<void> _exportComparisonSnapshot({
    required BuildContext context,
    required GlobalKey snapshotKey,
    required String baseFileName,
  }) async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final boundary =
          snapshotKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _snack(context, '비교 화면을 캡처하지 못했어요.');
        return;
      }
      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        _snack(context, '비교 화면을 캡처하지 못했어요.');
        return;
      }
      final ok = await downloadBytesAsFile(
        bytes: bytes,
        filename: '${_safeName(baseFileName)}_comparison.png',
        mimeType: 'image/png',
      );
      if (!context.mounted) return;
      _snack(
        context,
        ok
            ? '비교 화면 이미지를 저장했어요. (원본 영상 영역은 브라우저 보안상 비어 있을 수 있어요)'
            : '이미지 저장에 실패했어요. 다시 시도해 주세요.',
      );
    } catch (error) {
      debugPrint('[LOOPI] comparison snapshot failed: $error');
      if (context.mounted) {
        _snack(context, '비교 화면 저장 중 문제가 발생했어요.');
      }
    }
  }

  static String _safeName(String raw) {
    final cleaned = raw
        .trim()
        .replaceAll(RegExp(r'[^\w\-가-힣]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    if (cleaned.isEmpty) return 'loopi_practice';
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  static void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}