import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/community_models.dart';
import '../models/routine_category.dart';
import '../models/routine_models.dart';
import '../services/database_service.dart';
import '../utils/cached_video.dart';
import '../state/routine_library.dart';
import '../state/user_state.dart';
import '../theme/loopi_colors.dart';
import '../widgets/cached_remote_image.dart';
import '../widgets/category_filter_chips.dart';
import '../widgets/highlight_interval.dart';
import 'routine_player_screen.dart';
import 'user_profile_screen.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({
    super.key,
    required this.library,
    required this.userState,
    this.onPlayRoutine,
    this.refreshTick,
    this.onOpenUserFeed,
  });

  final RoutineLibrary library;
  final UserSubscriptionState userState;
  final ValueChanged<SavedRoutine>? onPlayRoutine;

  /// Bump this after a successful community share to force a reload.
  final ValueListenable<int>? refreshTick;
  final void Function(String authorId, String authorName)? onOpenUserFeed;

  @override
  State<CommunityScreen> createState() => CommunityScreenState();
}

class CommunityScreenState extends State<CommunityScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final DatabaseService _db = DatabaseService();
  final TextEditingController _searchController = TextEditingController();

  List<CommunityRoutinePost> _routines = [];
  List<CommunityShowcaseItem> _showcase = [];
  DocumentSnapshot<Map<String, dynamic>>? _showcaseCursor;
  DocumentSnapshot<Map<String, dynamic>>? _routinesCursor;
  final Set<String> _showcaseExclude = {};
  final Set<String> _routinesExclude = {};
  bool _routinesLoading = true;
  bool _routinesLoadingMore = false;
  bool _routinesHasMore = true;
  bool _showcaseLoading = true;
  bool _showcaseLoadingMore = false;
  bool _showcaseHasMore = true;
  String _query = '';
  String _category = RoutineCategory.all;
  Timer? _debounce;

  String? get _uid => widget.userState.uid;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    widget.refreshTick?.addListener(_onExternalRefresh);
    _reloadAll();
  }

  @override
  void didUpdateWidget(covariant CommunityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) {
      oldWidget.refreshTick?.removeListener(_onExternalRefresh);
      widget.refreshTick?.addListener(_onExternalRefresh);
    }
  }

  @override
  void dispose() {
    widget.refreshTick?.removeListener(_onExternalRefresh);
    _debounce?.cancel();
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onExternalRefresh() => unawaited(reload());

  Future<void> reload() => _reloadAll();

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 280), () {
      setState(() => _query = value.trim());
      _reloadAll();
    });
  }

  Future<void> _reloadAll() async {
    await Future.wait([_loadRoutines(), _loadShowcaseFirstPage()]);
  }

  Future<void> _loadRoutines() async {
    if (mounted) {
      setState(() {
        _routinesLoading = true;
        _routinesHasMore = true;
        _routinesCursor = null;
        _routinesExclude.clear();
      });
    }
    try {
      final page = await _db.fetchRoutinesFirstPage(
        searchQuery: _query,
        pageSize: DatabaseService.defaultPageSize,
        category: _category,
      );
      if (!mounted) return;
      setState(() {
        _routines = page.posts;
        _routinesExclude
          ..clear()
          ..addAll(page.posts.map((e) => e.id));
        _routinesCursor = page.cursor;
        _routinesHasMore = page.hasMore;
        _routinesLoading = false;
      });
    } catch (error) {
      debugPrint('Community routines load error: $error');
      if (mounted) setState(() => _routinesLoading = false);
    }
  }

  Future<void> _loadMoreRoutines() async {
    if (!_routinesHasMore || _routinesLoadingMore || _routinesLoading) return;
    setState(() => _routinesLoadingMore = true);
    final page = await _db.fetchRoutinesNextPage(
      cursor: _routinesCursor,
      excludeIds: _routinesExclude,
      searchQuery: _query,
      category: _category,
    );
    if (!mounted) return;
    setState(() {
      for (final post in page.posts) {
        if (_routinesExclude.add(post.id)) {
          _routines.add(post);
        }
      }
      _routinesCursor = page.cursor;
      _routinesHasMore = page.hasMore && page.posts.isNotEmpty;
      _routinesLoadingMore = false;
    });
  }

  Future<void> _loadShowcaseFirstPage() async {
    if (mounted) {
      setState(() {
        _showcaseLoading = true;
        _showcaseHasMore = true;
        _showcaseCursor = null;
        _showcaseExclude.clear();
      });
    }
    try {
      final page = await _db.fetchShowcaseFirstPage(
        searchQuery: _query,
        pageSize: DatabaseService.defaultPageSize,
        category: _category,
      );
      if (!mounted) return;
      setState(() {
        _showcase = page.items;
        _showcaseExclude
          ..clear()
          ..addAll(page.items.map((e) => e.id));
        _showcaseCursor = page.newestCursor;
        _showcaseHasMore = page.hasMore;
        _showcaseLoading = false;
      });
    } catch (error) {
      debugPrint('Community showcase load error: $error');
      if (mounted) setState(() => _showcaseLoading = false);
    }
  }

  Future<void> _loadMoreShowcase() async {
    if (!_showcaseHasMore || _showcaseLoadingMore || _showcaseLoading) return;
    setState(() => _showcaseLoadingMore = true);
    final page = await _db.fetchShowcaseNextPage(
      cursor: _showcaseCursor,
      excludeIds: _showcaseExclude,
      searchQuery: _query,
      category: _category,
    );
    if (!mounted) return;
    setState(() {
      for (final item in page.items) {
        if (_showcaseExclude.add(item.id)) {
          _showcase.add(item);
        }
      }
      _showcaseCursor = page.newestCursor;
      _showcaseHasMore = page.hasMore && page.items.isNotEmpty;
      _showcaseLoadingMore = false;
    });
  }

  Future<void> _toggleLike(CommunityShowcaseItem item) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('community.login_to_like'.tr())),
      );
      return;
    }
    final index = _showcase.indexWhere((e) => e.id == item.id);
    if (index < 0) return;
    final liked = item.isLikedBy(uid);
    final optimisticLikedBy = [...item.likedBy];
    if (liked) {
      optimisticLikedBy.remove(uid);
    } else {
      optimisticLikedBy.add(uid);
    }
    setState(() {
      _showcase[index] = item.copyWith(
        likedBy: optimisticLikedBy,
        likesCount: optimisticLikedBy.length,
      );
    });
    final updated = await _db.toggleShowcaseLike(itemId: item.id, uid: uid);
    if (!mounted || updated == null) return;
    final i = _showcase.indexWhere((e) => e.id == updated.id);
    if (i >= 0) setState(() => _showcase[i] = updated);
  }

  Future<void> _toggleFavorite(CommunityRoutinePost post) async {
    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('community.login_to_favorite'.tr())),
      );
      return;
    }
    final index = _routines.indexWhere((e) => e.id == post.id);
    if (index < 0) return;
    final favorited = post.isFavoritedBy(uid);
    final next = [...post.favoritedBy];
    if (favorited) {
      next.remove(uid);
    } else {
      next.add(uid);
    }
    setState(() {
      _routines[index] = post.copyWith(
        favoritedBy: next,
        favoriteCount: next.length,
        trendingFavorites7d: (post.trendingFavorites7d + (favorited ? -1 : 1)).clamp(0, 1 << 30),
      );
    });
    final updated = await _db.toggleCommunityFavorite(postId: post.id, uid: uid);
    if (!mounted || updated == null) return;
    final i = _routines.indexWhere((e) => e.id == updated.id);
    if (i >= 0) setState(() => _routines[i] = updated);
    unawaited(widget.library.setFavorite(post.routine.id, !favorited));
  }

  void _openRoutine(SavedRoutine routine) {
    if (widget.onPlayRoutine != null) {
      widget.onPlayRoutine!(routine);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutinePlayerScreen(routine: routine, library: widget.library),
      ),
    );
  }

  void _openShowcasePlayer(CommunityShowcaseItem item) {
    final url = item.playableUrl;
    if (url == null) {
      debugPrint(
        '[LOOPI] showcase play blocked id=${item.id} kind=${item.mediaKind.name} '
        'recordedPath=${item.recordedPath} videoUrl=${item.videoUrl}',
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            item.mediaKind == ShowcaseMediaKind.audio
                ? '오디오 파일을 찾을 수 없습니다. 다시 공유해 주세요.'
                : '이 녹화는 아직 재생할 수 없습니다.',
          ),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => _ShowcasePlayerDialog(item: item, url: url),
    );
  }

  void _openAuthor({required String authorId, required String authorName}) {
    if (authorId.isEmpty) return;
    if (widget.onOpenUserFeed != null) {
      widget.onOpenUserFeed!(authorId, authorName);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileScreen(
          authorId: authorId,
          authorName: authorName,
          library: widget.library,
          userState: widget.userState,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 1100
        ? 5
        : width >= 800
            ? 4
            : width >= 520
                ? 3
                : 2;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'community.search_hint'.tr(),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(height: 8),
        CategoryFilterBar(
          selected: _category,
          onSelected: (value) {
            if (_category == value) return;
            setState(() => _category = value);
            unawaited(_reloadAll());
          },
        ),
        TabBar(
          controller: _tabs,
          labelColor: LoopiColors.deepPurple,
          tabs: [
            Tab(text: 'community.tab_routines'.tr()),
            Tab(text: 'community.tab_showcase'.tr()),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _RoutinesTab(
                loading: _routinesLoading,
                loadingMore: _routinesLoadingMore,
                hasMore: _routinesHasMore,
                posts: _routines,
                uid: _uid,
                onRefresh: _loadRoutines,
                onLoadMore: _loadMoreRoutines,
                onOpen: (post) => _openRoutine(post.routine),
                onToggleFavorite: _toggleFavorite,
                onOpenAuthor: (post) => _openAuthor(
                  authorId: post.authorId,
                  authorName: post.authorName,
                ),
              ),
              _ShowcaseTab(
                loading: _showcaseLoading,
                loadingMore: _showcaseLoadingMore,
                hasMore: _showcaseHasMore,
                items: _showcase,
                crossAxisCount: crossAxisCount,
                uid: _uid,
                onRefresh: _loadShowcaseFirstPage,
                onLoadMore: _loadMoreShowcase,
                onToggleLike: _toggleLike,
                onOpenAuthor: (item) => _openAuthor(
                  authorId: item.authorId,
                  authorName: item.authorName,
                ),
                onPlay: _openShowcasePlayer,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoutinesTab extends StatelessWidget {
  const _RoutinesTab({
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.posts,
    required this.uid,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onOpen,
    required this.onToggleFavorite,
    required this.onOpenAuthor,
  });

  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final List<CommunityRoutinePost> posts;
  final String? uid;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final ValueChanged<CommunityRoutinePost> onOpen;
  final ValueChanged<CommunityRoutinePost> onToggleFavorite;
  final ValueChanged<CommunityRoutinePost> onOpenAuthor;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: LoopiColors.purple));
    }
    if (posts.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(child: Text('community.empty_routines'.tr())),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 240) {
            onLoadMore();
          }
          return false;
        },
        child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: posts.length + 1,
        itemBuilder: (context, index) {
          if (index >= posts.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: loadingMore
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: LoopiColors.purple),
                      )
                    : Text(
                        hasMore ? 'community.load_more'.tr() : 'community.loaded_all'.tr(),
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
              ),
            );
          }
          final post = posts[index];
          final favorited = post.isFavoritedBy(uid);
          final thumbUrl = post.routine.sourceType == SourceType.youtube &&
                  post.routine.videoId.isNotEmpty
              ? 'https://img.youtube.com/vi/${post.routine.videoId}/mqdefault.jpg'
              : null;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              onTap: () => onOpen(post),
              leading: thumbUrl == null
                  ? CircleAvatar(
                      backgroundColor: LoopiColors.purple.withValues(alpha: 0.15),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(color: LoopiColors.deepPurple, fontWeight: FontWeight.w800),
                      ),
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 52,
                        height: 40,
                        child: _NetworkThumb(
                          url: thumbUrl,
                          fallback: CircleAvatar(
                            backgroundColor: LoopiColors.purple.withValues(alpha: 0.15),
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(color: LoopiColors.deepPurple, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                    ),
              title: Text(post.routine.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 2),
                  InkWell(
                    onTap: () => onOpenAuthor(post),
                    child: Row(
                      children: [
                        _AuthorAvatar(url: post.authorPhotoUrl, name: post.authorName, radius: 10),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                      '@${post.authorName}',
                      style: const TextStyle(
                        color: LoopiColors.deepPurple,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: LoopiColors.deepPurple,
                      ),
                    ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    post.description.isEmpty ? 'community.no_description'.tr() : post.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (post.routine.hasHighlight) ...[
                    const SizedBox(height: 6),
                    const ChorusContainsBadge(compact: true),
                  ],
                ],
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: 'community.favorite_tooltip'.tr(),
                onPressed: () => onToggleFavorite(post),
                color: favorited ? LoopiColors.purple : null,
                icon: Icon(favorited ? Icons.bookmark : Icons.bookmark_border),
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}

class _ShowcaseTab extends StatelessWidget {
  const _ShowcaseTab({
    required this.loading,
    required this.loadingMore,
    required this.hasMore,
    required this.items,
    required this.crossAxisCount,
    required this.uid,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onToggleLike,
    required this.onOpenAuthor,
    required this.onPlay,
  });

  final bool loading;
  final bool loadingMore;
  final bool hasMore;
  final List<CommunityShowcaseItem> items;
  final int crossAxisCount;
  final String? uid;
  final Future<void> Function() onRefresh;
  final Future<void> Function() onLoadMore;
  final ValueChanged<CommunityShowcaseItem> onToggleLike;
  final ValueChanged<CommunityShowcaseItem> onOpenAuthor;
  final ValueChanged<CommunityShowcaseItem> onPlay;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: LoopiColors.purple));
    }
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 120),
            Center(child: Text('community.empty_showcase'.tr())),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 240) {
            onLoadMore();
          }
          return false;
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 0.78,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    return _ShowcaseTile(
                      item: item,
                      liked: item.isLikedBy(uid),
                      onLike: () => onToggleLike(item),
                      onOpenAuthor: () => onOpenAuthor(item),
                      onPlay: () => onPlay(item),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: loadingMore
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: LoopiColors.purple),
                        )
                      : Text(
                          hasMore ? 'community.load_more'.tr() : 'community.loaded_all'.tr(),
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShowcaseTile extends StatelessWidget {
  const _ShowcaseTile({
    required this.item,
    required this.liked,
    required this.onLike,
    required this.onOpenAuthor,
    required this.onPlay,
  });

  final CommunityShowcaseItem item;
  final bool liked;
  final VoidCallback onLike;
  final VoidCallback onOpenAuthor;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (item.mediaKind == ShowcaseMediaKind.audio)
            _AudioThumb(
              title: item.shortTitle,
              photoUrl: item.thumbnailUrl ?? item.thumbnailHint ?? item.authorPhotoUrl,
            )
          else
            _LightweightVideoThumb(
              path: item.playableUrl ?? item.recordedPath,
              thumbnailUrl: item.thumbnailUrl ?? item.thumbnailHint ?? item.authorPhotoUrl,
              fallbackTitle: item.shortTitle,
            ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: onPlay),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: onOpenAuthor,
                      child: Row(
                        children: [
                          _AuthorAvatar(url: item.authorPhotoUrl, name: item.authorName, radius: 8),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '@${item.authorName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                                decorationColor: Colors.white70,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: onLike,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.all_inclusive,
                            size: 18,
                            color: liked ? LoopiColors.purple : Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${item.likesCount}',
                            style: TextStyle(
                              color: liked ? LoopiColors.purple : Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (item.mediaKind == ShowcaseMediaKind.video)
            const Align(
              alignment: Alignment.center,
              child: Icon(Icons.play_circle_fill, color: Colors.white54, size: 36),
            ),
        ],
      ),
    );
  }
}

class _AudioThumb extends StatelessWidget {
  const _AudioThumb({required this.title, this.photoUrl});

  final String title;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final photo = photoUrl?.trim();
    final hasPhoto = photo != null &&
        (photo.startsWith('http://') || photo.startsWith('https://'));
    return ColoredBox(
      color: const Color(0xFF1A1524),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasPhoto)
            CachedRemoteImage(url: photo, fit: BoxFit.cover, memCacheWidth: 400),
          ColoredBox(
            color: Colors.black.withValues(alpha: hasPhoto ? 0.45 : 0.15),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.graphic_eq, color: Colors.white, size: 36),
                  const SizedBox(height: 8),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Avoids initializing [VideoPlayerController] per grid cell (UI freezes).
/// Uses cached network images for http(s) thumbs, otherwise a lightweight placeholder.
class _LightweightVideoThumb extends StatelessWidget {
  const _LightweightVideoThumb({
    required this.path,
    required this.fallbackTitle,
    this.thumbnailUrl,
  });

  final String? path;
  final String? thumbnailUrl;
  final String fallbackTitle;

  bool _isHttp(String? value) {
    if (value == null || value.isEmpty) return false;
    return value.startsWith('http://') || value.startsWith('https://');
  }

  /// Prefer a static image URL; skip video file URLs that would decode poorly.
  String? get _imageUrl {
    final thumb = thumbnailUrl;
    if (_isHttp(thumb)) return thumb;
    final p = path;
    if (!_isHttp(p)) return null;
    final lower = p!.toLowerCase();
    if (lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('.webm') ||
        lower.contains('.m3u8')) {
      return null;
    }
    return p;
  }

  @override
  Widget build(BuildContext context) {
    final url = _imageUrl;
    if (url != null) {
      return _NetworkThumb(
        url: url,
        fallback: _PlaceholderThumb(title: fallbackTitle),
      );
    }
    return _PlaceholderThumb(title: fallbackTitle);
  }
}

class _NetworkThumb extends StatelessWidget {
  const _NetworkThumb({required this.url, required this.fallback});

  final String url;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      memCacheWidth: 320,
      fadeInDuration: const Duration(milliseconds: 120),
      placeholder: (context, url) => const ColoredBox(
        color: Color(0xFF1A1524),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
          ),
        ),
      ),
      errorWidget: (context, url, error) => fallback,
    );
  }
}

class _PlaceholderThumb extends StatelessWidget {
  const _PlaceholderThumb({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1A1524),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.videocam_outlined, color: Colors.white38, size: 28),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthorAvatar extends StatelessWidget {
  const _AuthorAvatar({required this.url, required this.name, this.radius = 10});

  final String? url;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim().substring(0, 1);
    if (url != null && url!.isNotEmpty) {
      return ClipOval(
        child: CachedRemoteImage(
          url: url!,
          width: radius * 2,
          height: radius * 2,
          memCacheWidth: 64,
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: LoopiColors.purple.withValues(alpha: 0.2),
      child: Text(letter, style: TextStyle(fontSize: radius, fontWeight: FontWeight.w800, color: LoopiColors.deepPurple)),
    );
  }
}

class _ShowcasePlayerDialog extends StatefulWidget {
  const _ShowcasePlayerDialog({required this.item, required this.url});

  final CommunityShowcaseItem item;
  final String url;

  @override
  State<_ShowcasePlayerDialog> createState() => _ShowcasePlayerDialogState();
}

class _ShowcasePlayerDialogState extends State<_ShowcasePlayerDialog> {
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  bool _ready = false;
  bool _audioPlaying = false;
  String? _error;

  bool get _preferAudio =>
      widget.item.mediaKind == ShowcaseMediaKind.audio ||
      inferMediaKindFromPath(widget.url, audioHint: widget.item.mediaKind == ShowcaseMediaKind.audio) ==
          ShowcaseMediaKind.audio;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final url = widget.url;
    debugPrint(
      '[LOOPI] showcase player start id=${widget.item.id} kind=${widget.item.mediaKind.name} url=$url',
    );
    try {
      if (_preferAudio) {
        await _playAudio(url);
        return;
      }
      try {
        await _playVideo(url);
      } catch (error, stack) {
        debugPrint('[LOOPI] showcase video init failed, falling back to audio: $error\n$stack');
        await _video?.dispose();
        _video = null;
        await _playAudio(url);
      }
    } catch (error, stack) {
      debugPrint('[LOOPI] showcase player failed url=$url error=$error\n$stack');
      if (mounted) setState(() => _error = '재생에 실패했습니다. ($error)');
    }
  }

  Future<void> _playAudio(String url) async {
    _audio = AudioPlayer();
    await _audio!.play(UrlSource(url));
    _audioPlaying = true;
    _audio!.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _audioPlaying = false);
    });
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _playVideo(String url) async {
    _video = createCachedNetworkVideo(Uri.parse(url));
    await _video!.initialize();
    if (_video!.value.duration == Duration.zero && !_video!.value.isInitialized) {
      throw StateError('VideoPlayerController failed to initialize');
    }
    _video!.addListener(() {
      if (mounted) setState(() {});
    });
    await _video!.play();
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _toggleAudio() async {
    final player = _audio;
    if (player == null) return;
    if (_audioPlaying) {
      await player.pause();
      if (mounted) setState(() => _audioPlaying = false);
    } else {
      await player.resume();
      if (mounted) setState(() => _audioPlaying = true);
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final audioMode = _audio != null;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 720,
        height: 480,
        child: Column(
          children: [
            AppBar(
              automaticallyImplyLeading: false,
              title: Text(widget.item.title, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(_error!, style: const TextStyle(color: Colors.white70)),
                        )
                      : !_ready
                          ? const CircularProgressIndicator(color: Colors.white54)
                          : audioMode
                              ? const Icon(Icons.graphic_eq, color: Colors.white, size: 72)
                              : AspectRatio(
                                  aspectRatio: _video!.value.aspectRatio == 0
                                      ? 16 / 9
                                      : _video!.value.aspectRatio,
                                  child: VideoPlayer(_video!),
                                ),
                ),
              ),
            ),
            if (_ready && _video != null)
              IconButton(
                onPressed: () {
                  setState(() {
                    _video!.value.isPlaying ? _video!.pause() : _video!.play();
                  });
                },
                icon: Icon(_video!.value.isPlaying ? Icons.pause : Icons.play_arrow),
              )
            else if (_ready && _audio != null)
              IconButton(
                onPressed: _toggleAudio,
                icon: Icon(_audioPlaying ? Icons.pause : Icons.play_arrow),
              ),
          ],
        ),
      ),
    );
  }
}
