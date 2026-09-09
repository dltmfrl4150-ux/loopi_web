import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../models/community_models.dart';
import '../models/routine_models.dart';
import '../services/database_service.dart';
import '../state/routine_library.dart';
import '../state/user_state.dart';
import '../theme/loopi_colors.dart';
import '../utils/youtube_id.dart';
import '../widgets/cached_remote_image.dart';
import 'routine_player_screen.dart';

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({
    super.key,
    required this.authorId,
    required this.authorName,
    required this.library,
    required this.userState,
    this.onClose,
  });

  final String authorId;
  final String authorName;
  final RoutineLibrary library;
  final UserSubscriptionState userState;
  final VoidCallback? onClose;

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  late final TabController _tabs;
  List<CommunityRoutinePost> _routines = [];
  List<CommunityShowcaseItem> _showcase = [];
  DocumentSnapshot<Map<String, dynamic>>? _routinesCursor;
  DocumentSnapshot<Map<String, dynamic>>? _showcaseCursor;
  bool _routinesHasMore = true;
  bool _showcaseHasMore = true;
  bool _routinesLoadingMore = false;
  bool _showcaseLoadingMore = false;
  bool _loading = true;
  bool _selecting = false;
  bool _busy = false;
  final Set<String> _selectedRoutineIds = {};
  final Set<String> _selectedShowcaseIds = {};

  bool get _isOwnProfile {
    final uid = widget.userState.uid;
    return uid != null && uid.isNotEmpty && uid == widget.authorId;
  }

  bool _canDeleteAuthor(String authorId) {
    final uid = widget.userState.uid;
    return uid != null && uid.isNotEmpty && uid == authorId;
  }

  int get _selectedCount => _selectedRoutineIds.length + _selectedShowcaseIds.length;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (mounted) setState(() {});
    });
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _routinesHasMore = true;
      _showcaseHasMore = true;
      _routinesCursor = null;
      _showcaseCursor = null;
    });
    final results = await Future.wait([
      _db.fetchRoutinesByAuthorPage(
        authorId: widget.authorId,
        pageSize: DatabaseService.authorFeedPageSize,
      ),
      _db.fetchShowcaseByAuthorPage(
        authorId: widget.authorId,
        pageSize: DatabaseService.authorFeedPageSize,
      ),
    ]);
    if (!mounted) return;
    final routinesPage = results[0] as RoutinesPage;
    final showcasePage = results[1] as ShowcasePage;
    setState(() {
      _routines = routinesPage.posts;
      _showcase = showcasePage.items;
      _routinesCursor = routinesPage.cursor;
      _showcaseCursor = showcasePage.newestCursor;
      _routinesHasMore = routinesPage.hasMore;
      _showcaseHasMore = showcasePage.hasMore;
      _loading = false;
      _selectedRoutineIds.removeWhere((id) => !_routines.any((e) => e.id == id));
      _selectedShowcaseIds.removeWhere((id) => !_showcase.any((e) => e.id == id));
    });
  }

  Future<void> _loadMoreRoutines() async {
    if (!_routinesHasMore || _routinesLoadingMore || _loading) return;
    setState(() => _routinesLoadingMore = true);
    final page = await _db.fetchRoutinesByAuthorPage(
      authorId: widget.authorId,
      cursor: _routinesCursor,
    );
    if (!mounted) return;
    setState(() {
      final seen = _routines.map((e) => e.id).toSet();
      for (final post in page.posts) {
        if (seen.add(post.id)) _routines.add(post);
      }
      _routinesCursor = page.cursor;
      _routinesHasMore = page.hasMore && page.posts.isNotEmpty;
      _routinesLoadingMore = false;
    });
  }

  Future<void> _loadMoreShowcase() async {
    if (!_showcaseHasMore || _showcaseLoadingMore || _loading) return;
    setState(() => _showcaseLoadingMore = true);
    final page = await _db.fetchShowcaseByAuthorPage(
      authorId: widget.authorId,
      cursor: _showcaseCursor,
    );
    if (!mounted) return;
    setState(() {
      final seen = _showcase.map((e) => e.id).toSet();
      for (final item in page.items) {
        if (seen.add(item.id)) _showcase.add(item);
      }
      _showcaseCursor = page.newestCursor;
      _showcaseHasMore = page.hasMore && page.items.isNotEmpty;
      _showcaseLoadingMore = false;
    });
  }

  void _openRoutine(SavedRoutine routine) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutinePlayerScreen(routine: routine, library: widget.library),
      ),
    );
  }

  void _toggleSelectMode() {
    setState(() {
      _selecting = !_selecting;
      if (!_selecting) {
        _selectedRoutineIds.clear();
        _selectedShowcaseIds.clear();
      }
    });
  }

  void _toggleRoutineSelected(String id) {
    setState(() {
      if (_selectedRoutineIds.contains(id)) {
        _selectedRoutineIds.remove(id);
      } else {
        _selectedRoutineIds.add(id);
      }
    });
  }

  void _toggleShowcaseSelected(String id) {
    setState(() {
      if (_selectedShowcaseIds.contains(id)) {
        _selectedShowcaseIds.remove(id);
      } else {
        _selectedShowcaseIds.add(id);
      }
    });
  }

  Future<void> _confirmDeleteSelected() {
    return _deleteCommunityItems(
      routineIds: _selectedRoutineIds.toList(),
      showcaseIds: _selectedShowcaseIds.toList(),
    );
  }

  Future<void> _deleteCommunityItems({
    List<String> routineIds = const [],
    List<String> showcaseIds = const [],
  }) async {
    final count = routineIds.length + showcaseIds.length;
    if (count == 0 || _busy) return;
    final uid = widget.userState.uid;
    if (uid == null || uid.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('커뮤니티에서 삭제'),
        content: Text('Are you sure you want to remove this from the Community? ($count)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    final deleted = await _db.deleteCommunityItemsBatch(
      requesterId: uid,
      routineIds: routineIds,
      showcaseIds: showcaseIds,
    );
    if (!mounted) return;
    setState(() {
      _routines.removeWhere((e) => routineIds.contains(e.id));
      _showcase.removeWhere((e) => showcaseIds.contains(e.id));
      _selectedRoutineIds.removeAll(routineIds);
      _selectedShowcaseIds.removeAll(showcaseIds);
      if (_selectedCount == 0) _selecting = false;
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted > 0 ? 'Removed from Community successfully.' : '삭제에 실패했습니다. 다시 시도해 주세요.',
        ),
      ),
    );
  }

  bool _onRoutinesScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 240) {
      unawaited(_loadMoreRoutines());
    }
    return false;
  }

  bool _onShowcaseScroll(ScrollNotification notification) {
    if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 240) {
      unawaited(_loadMoreShowcase());
    }
    return false;
  }

  Widget _pagingFooter(bool loadingMore, bool hasMore) {
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

  Widget _routineThumb(CommunityRoutinePost post) {
    final url = youtubeThumbnailUrl(post.routine.videoId) ?? youtubeThumbnailUrl(post.routine.videoUrl);
    if (url == null) {
      return const Icon(Icons.play_circle_outline, color: LoopiColors.purple);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedRemoteImage(url: url, width: 52, height: 40, memCacheWidth: 120),
    );
  }

  Future<void> _reorderRoutines(int oldIndex, int newIndex) async {
    setState(() {
      final item = _routines.removeAt(oldIndex);
      _routines.insert(newIndex, item);
    });
    final uid = widget.userState.uid;
    if (uid == null) return;
    await _db.updateRoutineDisplayOrder(
      requesterId: uid,
      orderedIds: _routines.map((e) => e.id).toList(),
    );
  }

  Future<void> _reorderShowcase(int from, int to) async {
    if (from == to) return;
    setState(() {
      final item = _showcase.removeAt(from);
      _showcase.insert(to, item);
    });
    final uid = widget.userState.uid;
    if (uid == null) return;
    await _db.updateShowcaseDisplayOrder(
      requesterId: uid,
      orderedIds: _showcase.map((e) => e.id).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width >= 900
        ? 4
        : width >= 600
            ? 3
            : 2;

    return PopScope(
      canPop: widget.onClose == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.onClose?.call();
      },
      child: Scaffold(
      backgroundColor: LoopiColors.canvas,
      appBar: AppBar(
        title: Text('@${widget.authorName}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (widget.onClose != null) {
              widget.onClose!();
            } else if (Navigator.canPop(context)) {
              Navigator.of(context).pop();
            }
          },
        ),
        actions: [
          if (_isOwnProfile)
            IconButton(
              tooltip: _selecting ? '선택 취소' : '게시물 관리',
              onPressed: _toggleSelectMode,
              icon: Icon(_selecting ? Icons.close : Icons.delete_outline),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: LoopiColors.purple.withValues(alpha: 0.15),
                  child: Text(
                    widget.authorName.isEmpty ? '?' : widget.authorName.substring(0, 1),
                    style: const TextStyle(
                      color: LoopiColors.deepPurple,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.authorName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '공개 루틴 ${_routines.length} · 쇼케이스 ${_showcase.length}',
                        style: TextStyle(color: LoopiColors.muted),
                      ),
                      if (_isOwnProfile && !_selecting)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '핸들을 드래그해 순서를 바꿀 수 있어요.',
                            style: TextStyle(color: LoopiColors.muted, fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          TabBar(
            controller: _tabs,
            labelColor: LoopiColors.deepPurple,
            tabs: const [
              Tab(text: '루틴'),
              Tab(text: '쇼케이스'),
            ],
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: LoopiColors.purple))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildRoutinesTab(),
                      _buildShowcaseTab(crossAxisCount),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _selecting ? _selectionBar() : null,
    ),
    );
  }

  Widget _selectionBar() {
    return SafeArea(
      child: Material(
        elevation: 8,
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              TextButton(
                onPressed: _busy ? null : _toggleSelectMode,
                child: const Text('Cancel'),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _busy || _selectedCount == 0 ? null : _confirmDeleteSelected,
                style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.delete_outline),
                label: Text('Delete Selected ($_selectedCount)'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoutinesTab() {
    if (_routines.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('공유된 루틴이 없습니다.')),
          ],
        ),
      );
    }

    if (_isOwnProfile && !_selecting) {
      return RefreshIndicator(
        onRefresh: _load,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onRoutinesScroll,
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: _routines.length,
            onReorderItem: _reorderRoutines,
            buildDefaultDragHandles: false,
            itemBuilder: (context, index) {
              final post = _routines[index];
              return ReorderableDelayedDragStartListener(
                key: ValueKey(post.id),
                index: index,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () => _openRoutine(post.routine),
                    leading: _routineThumb(post),
                    title: Text(post.routine.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      post.description.isEmpty ? '설명 없음' : post.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_canDeleteAuthor(post.authorId))
                          IconButton(
                            tooltip: '삭제',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy ? null : () => _deleteCommunityItems(routineIds: [post.id]),
                          ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Icon(Icons.drag_handle),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onRoutinesScroll,
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          itemCount: _routines.length + 1,
          itemBuilder: (context, index) {
            if (index >= _routines.length) return _pagingFooter(_routinesLoadingMore, _routinesHasMore);
            final post = _routines[index];
            final selected = _selectedRoutineIds.contains(post.id);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                onTap: _selecting
                    ? () => _toggleRoutineSelected(post.id)
                    : () => _openRoutine(post.routine),
                leading: _selecting
                    ? Checkbox(
                        value: selected,
                        onChanged: (_) => _toggleRoutineSelected(post.id),
                        activeColor: LoopiColors.purple,
                      )
                    : _routineThumb(post),
                title: Text(post.routine.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  post.description.isEmpty ? '설명 없음' : post.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _selecting ? null : const Icon(Icons.chevron_right),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildShowcaseTab(int crossAxisCount) {
    if (_showcase.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('공유된 쇼케이스가 없습니다.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: NotificationListener<ScrollNotification>(
        onNotification: _onShowcaseScroll,
        child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.85,
        ),
        itemCount: _showcase.length,
        itemBuilder: (context, index) {
          final item = _showcase[index];
          final selected = _selectedShowcaseIds.contains(item.id);
          final tile = _ShowcaseProfileTile(
            item: item,
            selecting: _selecting,
            selected: selected,
            showDragHandle: _isOwnProfile && !_selecting,
            onDelete: !_selecting && _canDeleteAuthor(item.authorId)
                ? () => _deleteCommunityItems(showcaseIds: [item.id])
                : null,
          );

          if (_selecting) {
            return GestureDetector(
              onTap: () => _toggleShowcaseSelected(item.id),
              child: tile,
            );
          }

          if (_isOwnProfile) {
            return LongPressDraggable<int>(
              data: index,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 140,
                  height: 160,
                  child: Opacity(opacity: 0.9, child: tile),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.35, child: tile),
              child: DragTarget<int>(
                onWillAcceptWithDetails: (details) => details.data != index,
                onAcceptWithDetails: (details) => _reorderShowcase(details.data, index),
                builder: (context, candidate, _) {
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: candidate.isNotEmpty
                          ? Border.all(color: LoopiColors.purple, width: 2)
                          : null,
                    ),
                    child: tile,
                  );
                },
              ),
            );
          }

          return tile;
        },
      ),
      ),
    );
  }
}

class _ShowcaseProfileTile extends StatelessWidget {
  const _ShowcaseProfileTile({
    required this.item,
    required this.selecting,
    required this.selected,
    required this.showDragHandle,
    this.onDelete,
  });

  final CommunityShowcaseItem item;
  final bool selecting;
  final bool selected;
  final bool showDragHandle;
  final VoidCallback? onDelete;

  Widget _thumb() {
    final url = item.thumbnailUrl ?? item.thumbnailHint ?? item.authorPhotoUrl;
    if (url == null || url.isEmpty || !(url.startsWith('http://') || url.startsWith('https://'))) {
      return ColoredBox(
        color: const Color(0xFF1A1524),
        child: item.mediaKind == ShowcaseMediaKind.audio
            ? const Center(child: Icon(Icons.graphic_eq, color: Colors.white70, size: 36))
            : null,
      );
    }
    return CachedRemoteImage(url: url, fit: BoxFit.cover, memCacheWidth: 400);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ColoredBox(
        color: item.mediaKind == ShowcaseMediaKind.audio ? Colors.black : const Color(0xFF1A1524),
        child: Stack(
          children: [
            Positioned.fill(
              child: item.mediaKind == ShowcaseMediaKind.audio
                  ? const ColoredBox(color: Colors.black)
                  : _thumb(),
            ),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    item.mediaKind == ShowcaseMediaKind.audio
                        ? Icons.graphic_eq
                        : Icons.videocam_outlined,
                    color: Colors.white70,
                  ),
                  const Spacer(),
                  Text(
                    item.shortTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '∞ ${item.likesCount}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (selecting)
              Positioned(
                top: 6,
                right: 6,
                child: IgnorePointer(
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) {},
                    side: const BorderSide(color: Colors.white70),
                    fillColor: WidgetStateProperty.resolveWith(
                      (states) => states.contains(WidgetState.selected)
                          ? LoopiColors.purple
                          : Colors.black45,
                    ),
                  ),
                ),
              )
            else if (onDelete != null)
              Positioned(
                top: 2,
                right: 2,
                child: IconButton(
                  tooltip: '삭제',
                  icon: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                  onPressed: onDelete,
                ),
              )
            else if (showDragHandle)
              const Positioned(
                top: 6,
                right: 6,
                child: Icon(Icons.drag_indicator, color: Colors.white54, size: 20),
              ),
          ],
        ),
      ),
    );
  }
}
