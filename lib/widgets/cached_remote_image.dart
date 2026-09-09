import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/loopi_colors.dart';
import '../utils/youtube_id.dart';

/// Cached remote image used for routine / showcase thumbs and avatars.
class CachedRemoteImage extends StatelessWidget {
  const CachedRemoteImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth = 320,
    this.borderRadius,
    this.placeholder,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final int memCacheWidth;
  final BorderRadius? borderRadius;
  final Widget? placeholder;

  static String? youtubeThumb(String? videoIdOrUrl) => youtubeThumbnailUrl(videoIdOrUrl);

  @override
  Widget build(BuildContext context) {
    final fallback = placeholder ??
        ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: Icon(Icons.play_circle_fill_rounded, color: LoopiColors.purple),
          ),
        );
    final image = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memCacheWidth,
      fadeInDuration: const Duration(milliseconds: 80),
      placeholder: (context, url) => fallback,
      errorWidget: (context, url, error) => fallback,
    );
    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }
}
