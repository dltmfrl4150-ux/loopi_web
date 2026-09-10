import 'dart:async';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/routine_models.dart';
import '../models/routine_category.dart';
import '../models/community_models.dart';
import '../services/database_service.dart';
import '../state/routine_library.dart';
import '../state/user_state.dart';
import '../theme/loopi_colors.dart';
import '../utils/media_limits.dart';
import '../utils/time_format.dart';
import '../utils/youtube_id.dart';
import '../widgets/app_logo.dart';
import '../widgets/cached_remote_image.dart';
import '../widgets/favorite_icon_button.dart';
import '../widgets/category_filter_chips.dart';
import '../widgets/highlight_interval.dart';
import '../widgets/shell_close_scope.dart';
import 'community_screen.dart';
import 'link_studio_screen.dart';
import 'my_profile_screen.dart';
import 'practice_mode_screen.dart';
import 'practice_screen.dart';
import 'routine_player_screen.dart';
import 'user_profile_screen.dart';

enum SelectionMode { none, group, delete }

class CommunityPost {
  CommunityPost({required this.routine, required this.description})
      : createdAt = DateTime.now();

  final SavedRoutine routine;
  final String description;
  final DateTime createdAt;

  String get authorId => routine.authorId;
  String get authorName => routine.authorName;
}

class CommunityFeedStore extends ChangeNotifier {
  final List<CommunityPost> _posts = [];

  List<CommunityPost> get posts => List.unmodifiable(_posts);

  void add(CommunityPost post) {
    _posts.insert(0, post);
    notifyListeners();
  }

  void toggleFavorite(SavedRoutine routine, bool value, RoutineLibrary library, BuildContext context) async {
    await library.setFavorite(routine.id, value);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value ? 'common.favorite_added'.tr() : 'common.favorite_removed'.tr())),
    );
  }
}

class HomeDashboardScreen extends StatefulWidget {
  const HomeDashboardScreen({
    super.key,
    required this.library,
    required this.userState,
    this.onSignedOut,
  });

  final RoutineLibrary library;
  final UserSubscriptionState userState;
  final Future<void> Function()? onSignedOut;

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen> {
  int _tabIndex = 0;
  Widget? _shellPage;
  final CommunityFeedStore _communityFeed = CommunityFeedStore();
  final DatabaseService _database = DatabaseService();
  final ValueNotifier<int> _communityRefreshTick = ValueNotifier<int>(0);

  @override
  void dispose() {
    _communityRefreshTick.dispose();
    super.dispose();
  }

  void _bumpCommunityRefresh() {
    _communityRefreshTick.value++;
  }

  Future<void> _shareRoutine(SavedRoutine routine) async {
    final controller = TextEditingController();
    final description = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('library.share_routine_title'.tr(namedArgs: {'name': routine.name})),
        content: TextField(
          controller: controller,
          maxLength: 50,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'library.share_routine_hint'.tr(),
            counterText: null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('common.cancel'.tr())),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: Text('library.share_routine_action'.tr())),
        ],
      ),
    );
    controller.dispose();
    if (description == null) return;
    final authorId = widget.userState.uid ?? 'guest';
    final authorName = widget.userState.nickname;
    await _database.shareRoutineToCommunity(
      routine: routine,
      description: description,
      authorId: authorId,
      authorName: authorName,
      authorPhotoUrl: widget.userState.photoUrl,
    );
    _communityFeed.add(CommunityPost(routine: routine, description: description));
    _bumpCommunityRefresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('library.share_routine_success'.tr())));
    }
  }

  Future<void> _sharePracticeResult(PracticeResult result) async {
    var category = RoutineCategory.normalize(
      widget.library.byId(result.routineId)?.category ?? result.category,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('library.share_practice_title'.tr()),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('library.share_practice_message'.tr(namedArgs: {'name': result.name})),
                  const SizedBox(height: 16),
                  Text(
                    'category.label'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  CategoryChoiceChips(
                    selected: category,
                    onSelected: (value) => setDialogState(() => category = value),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: Text('common.cancel'.tr()),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: Text('common.share'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) return;
    try {
      await _database.sharePracticeToShowcase(
        result: result,
        authorId: widget.userState.uid ?? 'guest',
        authorName: widget.userState.nickname,
        authorPhotoUrl: widget.userState.photoUrl,
        mediaKind: result.isAudioRecording
            ? ShowcaseMediaKind.audio
            : inferMediaKindFromPath(result.recordedPath),
        category: category,
        routine: widget.library.byId(result.routineId),
      );
      _bumpCommunityRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('library.share_practice_success'.tr())),
      );
    } catch (error) {
      debugPrint('[LOOPI] share practice to Showcase failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('쇼케이스 업로드에 실패했습니다. 다시 시도해 주세요.')),
      );
    }
  }

  void _openLinkStudio({
    SourceType sourceType = SourceType.youtube,
    PlatformFile? file,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LinkStudioScreen(
          library: widget.library,
          sourceType: sourceType,
          file: file,
        ),
      ),
    );
  }

  void _openEditRoutine(SavedRoutine routine) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LinkStudioScreen(
          library: widget.library,
          editingRoutine: routine,
          initialVideoUrl: routine.videoUrl.isNotEmpty ? routine.videoUrl : kDefaultVideoUrl,
          sourceType: routine.sourceType,
          localFilePath: routine.localFilePath,
          fileName: routine.fileName,
        ),
      ),
    );
  }

  Future<void> _pickVideoFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: false,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.single;
      _openLinkStudio(sourceType: SourceType.localVideo, file: file);
    }
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac', 'mp4', 'mov', 'webm'],
      allowMultiple: false,
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      final file = result.files.single;
      _openLinkStudio(sourceType: SourceType.audio, file: file);
    }
  }

  void _startRoutine(SavedRoutine routine) {
    _openPracticeView(
      PracticeScreen(
        library: widget.library,
        selectedRoutine: routine,
        onOpenInShell: _openInShell,
        profilePhotoUrl: widget.userState.photoUrl,
      ),
    );
  }

  void _openUserFeed(String authorId, String authorName) {
    if (authorId.isEmpty) return;
    _openInShell(
      UserProfileScreen(
        authorId: authorId,
        authorName: authorName,
        library: widget.library,
        userState: widget.userState,
        onClose: _closeShell,
      ),
    );
  }

  void _openInShell(Widget page) {
    // When a shell page is already open (e.g. practice → comparison), only swap
    // content. Calling popUntil here disposes the practice screen mid-callback
    // and can trigger the red error screen.
    if (_shellPage == null) {
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      }
    }
    if (!mounted) return;
    setState(() {
      _shellPage = ShellCloseScope(close: _closeShell, child: page);
    });
  }

  void _closeShell() {
    if (_shellPage == null) return;
    setState(() => _shellPage = null);
  }

  void _openRoutinePlayer(SavedRoutine routine) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutinePlayerScreen(
          routine: routine,
          library: widget.library,
          onOpenInShell: _openInShell,
        ),
      ),
    );
  }

  void _openLibraryTab() {
    setState(() {
      _shellPage = null;
      _tabIndex = 3;
    });
  }

  void _openPracticeView(Widget view) {
    _openInShell(view);
  }

  void _onTabSelected(int index) {
    setState(() {
      _shellPage = null;
      _tabIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _shellPage != null
          ? null
          : AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        titleSpacing: 16,
        title: const Align(
          alignment: Alignment.centerLeft,
          child: AppLogo(height: 30),
        ),
        actions: [
          IconButton(
            onPressed: () {},
            tooltip: 'home.tooltip_notifications'.tr(),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MyProfileScreen(
                  userState: widget.userState,
                  library: widget.library,
                  onSignedOut: widget.onSignedOut,
                  onOpenUserFeed: (authorId, authorName) {
                    Navigator.of(context).pop();
                    _openUserFeed(authorId, authorName);
                  },
                ),
              ),
            ),
            tooltip: 'home.tooltip_profile'.tr(),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _shellPage ??
            IndexedStack(
          index: _tabIndex,
          children: [
            _HomeTab(
              library: widget.library,
              onCreateRoutine: _openLinkStudio,
              onStartRoutine: _startRoutine,
              onCreateVideoRoutine: _pickVideoFile,
              onCreateAudioRoutine: _pickAudioFile,
              onOpenRoutinePlayer: _openRoutinePlayer,
              onViewAll: _openLibraryTab,
            ),
            LinkStudioScreen(
              library: widget.library,
              embedded: true,
              active: _tabIndex == 1,
            ),
            CommunityScreen(
              library: widget.library,
              userState: widget.userState,
              onPlayRoutine: _openRoutinePlayer,
              refreshTick: _communityRefreshTick,
              onOpenUserFeed: _openUserFeed,
            ),
            _LibraryTab(
              library: widget.library,
              onStartRoutine: _startRoutine,
              onShareRoutine: _shareRoutine,
              onSharePracticeResult: _sharePracticeResult,
              onEditRoutine: _openEditRoutine,
              onFavorite: (routine, value) => _communityFeed.toggleFavorite(routine, value, widget.library, context),
              onOpenPracticeView: _openPracticeView,
              onOpenRoutinePlayer: _openRoutinePlayer,
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: _onTabSelected,
        indicatorColor: scheme.primary.withValues(alpha: 0.18),
        destinations: [
          NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home),
          label: 'home.tab_home'.tr(), //
        ),
        NavigationDestination(
          icon: const Icon(Icons.movie_creation_outlined),
          selectedIcon: const Icon(Icons.movie_creation),
          label: 'home.tab_studio'.tr(),
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'home.tab_community'.tr(),
        ),
        NavigationDestination(
          icon: Icon(Icons.bookmark_outline),
          selectedIcon: Icon(Icons.bookmark),
          label: 'library.title'.tr(),
        ),
        ],
      ),
    );
  }

}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.library,
    required this.onCreateRoutine,
    required this.onStartRoutine,
    required this.onCreateVideoRoutine,
    required this.onCreateAudioRoutine,
    required this.onOpenRoutinePlayer,
    required this.onViewAll,
  });

  final RoutineLibrary library;
  final VoidCallback onCreateRoutine;
  final ValueChanged<SavedRoutine> onStartRoutine;
  final VoidCallback onCreateVideoRoutine;
  final VoidCallback onCreateAudioRoutine;
  final ValueChanged<SavedRoutine> onOpenRoutinePlayer;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.62);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      children: [
        Text('home.greeting'.tr(), style: TextStyle(color: muted, fontSize: 15)),
        const SizedBox(height: 4),
        Text(
          'home.subtitle'.tr(),
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 20),
        const _AnnouncementBanner(),
        const SizedBox(height: 20),
        Text(
          'home.quick_action'.tr(),
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        _MediaSourceCards(
          onYouTubeTap: onCreateRoutine,
          onVideoTap: onCreateVideoRoutine,
          onAudioTap: onCreateAudioRoutine,
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'home.recent_routines'.tr(),
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            TextButton(onPressed: onViewAll, child: Text('home.view_all'.tr())),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedBuilder(
          animation: library,
          builder: (context, _) {
            if (library.routines.isEmpty) {
              return _EmptyRoutineCard(onTap: onCreateRoutine);
            }
            return Column(
              children: [
                for (final routine in library.routines.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RoutineCard(
                      routine: routine,
                      library: library,
                      onStart: () => onOpenRoutinePlayer(routine),
                      onPractice: () => onStartRoutine(routine),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _AnnouncementBanner extends StatefulWidget {
  const _AnnouncementBanner();

  @override
  State<_AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<_AnnouncementBanner> {
  final DatabaseService _database = DatabaseService();
  AppAnnouncement? _announcement;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  Future<void> _load() async {
    final locale = context.locale.languageCode;
    final latest = await _database.fetchLatestAnnouncement(locale: locale);
    if (!mounted) return;
    setState(() {
      _announcement = latest;
      _loading = false;
    });
  }

  Future<void> _openLink(String raw) async {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = (_announcement?.title.isNotEmpty == true)
        ? _announcement!.title
        : 'home.announcement_fallback'.tr();
    final link = _announcement?.link;
    final tappable = link != null && link.isNotEmpty;

    return Semantics(
      label: 'home.announcement_semantics'.tr(),
      button: tappable,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: tappable ? () => unawaited(_openLink(link)) : null,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [
                  LoopiColors.purple.withValues(alpha: 0.12),
                  kHighlightPink.withValues(alpha: 0.08),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              border: Border.all(
                color: LoopiColors.purple.withValues(alpha: 0.28),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: LoopiColors.purple.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.campaign_rounded,
                      color: LoopiColors.purpleDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _loading
                        ? Text(
                            'home.announcement_fallback'.tr(),
                            style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.72),
                              fontSize: 14,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : Text(
                            text,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 14,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  if (tappable) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaSourceCards extends StatelessWidget {
  const _MediaSourceCards({
    required this.onYouTubeTap,
    required this.onVideoTap,
    required this.onAudioTap,
  });

  final VoidCallback onYouTubeTap;
  final VoidCallback onVideoTap;
  final VoidCallback onAudioTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _MediaSourceCard(
            icon: Icons.play_circle_rounded,
            title: 'home.create_routine_youtube'.tr(),
            subtitle: 'home.create_routine_youtube_subtitle'.tr(),
            color: LoopiColors.purple,
            onTap: onYouTubeTap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MediaSourceCard(
            icon: Icons.videocam_rounded,
            title: 'home.create_routine_video'.tr(),
            subtitle: 'home.create_routine_video_subtitle'.tr(),
            color: LoopiColors.deepPurple,
            onTap: onVideoTap,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MediaSourceCard(
            icon: Icons.graphic_eq_rounded,
            title: 'home.create_routine_audio'.tr(),
            subtitle: 'home.create_routine_audio_subtitle'.tr(),
            color: LoopiColors.purple.withValues(alpha: 0.8),
            onTap: onAudioTap,
          ),
        ),
      ],
    );
  }
}

class _MediaSourceCard extends StatelessWidget {
  const _MediaSourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final content = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 28),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFE8E0FF),
                    fontSize: 11,
                    height: 1.2,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
            if (!constraints.maxHeight.isFinite) return content;
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: SizedBox(
                width: constraints.maxWidth,
                child: content,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _EmptyRoutineCard extends StatelessWidget {
  const _EmptyRoutineCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.play_circle_outline_rounded, color: LoopiColors.purple, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'home.no_routines'.tr(),
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineCard extends StatelessWidget {
  const _RoutineCard({
    required this.routine,
    required this.onStart,
    required this.library,
    this.isSelected = false,
    this.onTap,
    this.onPractice,
    this.onShare,
    this.onFavorite,
    this.onEdit,
  });

  final SavedRoutine routine;
  final VoidCallback onStart;
  final RoutineLibrary library;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onPractice;
  final VoidCallback? onShare;
  final ValueChanged<bool>? onFavorite;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final first = routine.segments.first;
    final last = routine.segments.last;
    final rangeLabel =
        '${formatMmSs(first.startSec)} – ${formatMmSs(last.endSec)} · ${'common.interval_count'.tr(namedArgs: {'count': '${routine.segments.length}'})}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: LoopiColors.purple, width: 2)
              : null,
        ),
        child: Row(
          children: [
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(Icons.check_circle, color: LoopiColors.purple),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: routine.sourceType == SourceType.youtube &&
                      (youtubeThumbnailUrl(routine.videoId) ?? youtubeThumbnailUrl(routine.videoUrl)) != null
                  ? CachedRemoteImage(
                      url: youtubeThumbnailUrl(routine.videoId) ?? youtubeThumbnailUrl(routine.videoUrl)!,
                      width: 72,
                      height: 52,
                      memCacheWidth: 160,
                    )
                  : Container(
                      width: 72,
                      height: 52,
                      color: scheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(
                        routine.sourceType == SourceType.audio
                            ? Icons.graphic_eq_rounded
                            : Icons.videocam_rounded,
                        color: LoopiColors.purple,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routine.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    rangeLabel,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                  ),
                  if (routine.hasHighlight) ...[
                    const SizedBox(height: 6),
                    const ChorusContainsBadge(compact: true),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (onEdit != null)
              IconButton(
                onPressed: onEdit,
                tooltip: 'library.tooltip_edit'.tr(),
                icon: const Icon(Icons.edit_outlined),
              ),
            if (onShare != null)
              IconButton(
                onPressed: onShare,
                tooltip: 'library.tooltip_share'.tr(),
                icon: const Icon(Icons.share_outlined),
              ),
            if (onFavorite != null)
              FavoriteButton(
                initialValue: routine.isFavorite,
                onChanged: (value) => onFavorite!(value),
              ),
            if (onTap == null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton(
                    onPressed: onStart,
                    style: FilledButton.styleFrom(
                      backgroundColor: LoopiColors.purple,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Play'),
                  ),
                  if (onPractice != null) ...[
                    const SizedBox(width: 4),
                    OutlinedButton(
                      onPressed: onPractice,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: LoopiColors.purple,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Practice'),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _LibraryTab extends StatefulWidget {
  const _LibraryTab({
    required this.library,
    required this.onStartRoutine,
    required this.onShareRoutine,
    required this.onSharePracticeResult,
    required this.onEditRoutine,
    required this.onFavorite,
    required this.onOpenPracticeView,
    required this.onOpenRoutinePlayer,
  });

  final RoutineLibrary library;
  final ValueChanged<SavedRoutine> onStartRoutine;
  final ValueChanged<SavedRoutine> onShareRoutine;
  final ValueChanged<PracticeResult> onSharePracticeResult;
  final ValueChanged<SavedRoutine> onEditRoutine;
  final void Function(SavedRoutine routine, bool value) onFavorite;
  final ValueChanged<Widget> onOpenPracticeView;
  final ValueChanged<SavedRoutine> onOpenRoutinePlayer;

  @override
  State<_LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<_LibraryTab> with SingleTickerProviderStateMixin {
  SelectionMode _selectionMode = SelectionMode.none;
  final Set<String> _selectedIds = {};
  late final TabController _libraryTabs;
  String _category = RoutineCategory.all;
  int _practiceVisibleCount = kFeedPageSize;

  @override
  void initState() {
    super.initState();
    _libraryTabs = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _libraryTabs.dispose();
    super.dispose();
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _enterSelectionMode(SelectionMode mode) {
    setState(() {
      _selectionMode = mode;
      _selectedIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = SelectionMode.none;
      _selectedIds.clear();
    });
  }

  void _openRoutinePlayer(SavedRoutine routine) {
    widget.onOpenRoutinePlayer(routine);
  }

  Future<void> _handleGroupConfirm() async {
    if (_selectedIds.isEmpty) return;
    
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('library.create_group'.tr()),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(hintText: 'library.group_name_hint'.tr()),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('library.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            child: Text('library.confirm'.tr()),
          ),
        ],
      ),
    );
    
    if (name?.isNotEmpty == true) {
      widget.library.createGroup(name: name!, routineIds: _selectedIds.toList());
    }
    _exitSelectionMode();
  }

  Future<void> _handleDeleteConfirm() async {
    if (_selectedIds.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('library.delete_confirm_title'.tr()),
        content: Text('library.delete_confirm_message'.tr().replaceAll('N', '${_selectedIds.length}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('library.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('library.delete'.tr()),
          ),
        ],
      ),
    );
    
    if (confirmed == true) {
      // Separate routine IDs from practice result IDs
      final routineIds = <String>[];
      final practiceResultIds = <String>[];
      
      for (final id in _selectedIds) {
        if (id.startsWith('practice_')) {
          practiceResultIds.add(id);
        } else {
          routineIds.add(id);
        }
      }
      
      // Delete routines
      if (routineIds.isNotEmpty) {
        widget.library.deleteMany(routineIds.toSet());
      }
      
      // Delete practice results
      if (practiceResultIds.isNotEmpty) {
        widget.library.deleteManyPracticeResults(practiceResultIds.toSet());
      }
    }
    _exitSelectionMode();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.library,
      builder: (context, _) {
        bool matchesRoutine(SavedRoutine routine) =>
            RoutineCategory.matches(routine.category, _category);
        bool matchesPractice(PracticeResult result) => RoutineCategory.matches(
              widget.library.byId(result.routineId)?.category ?? result.category,
              _category,
            );
        final groups = [
          for (final group in widget.library.groups)
            if (widget.library.routinesForGroup(group).any(matchesRoutine)) group,
        ];
        final ungrouped = widget.library.ungroupedRoutines.where(matchesRoutine).toList();
        final favorites = widget.library.favoriteRoutines.where(matchesRoutine).toList();
        final practiceResults = widget.library.practiceResults.where(matchesPractice).toList();
        final visiblePractice = practiceResults.take(_practiceVisibleCount).toList();
        final hasAnyRoutines = widget.library.routines.isNotEmpty;

        if (!hasAnyRoutines) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _EmptyRoutineCard(onTap: () {}),
              ],
            ),
          );
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
              child: Row(
                children: [
                  Text(
                    'library.title'.tr(),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  if (_selectionMode == SelectionMode.none) ...[
                    IconButton(
                      onPressed: () => _enterSelectionMode(SelectionMode.group),
                      icon: const Icon(Icons.folder_shared),
                      tooltip: 'library.tooltip_group'.tr(),
                    ),
                    IconButton(
                      onPressed: () => _enterSelectionMode(SelectionMode.delete),
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'library.tooltip_delete'.tr(),
                    ),
                  ] else ...[
                    if (_selectionMode == SelectionMode.group)
                      IconButton(
                        onPressed: _handleGroupConfirm,
                        icon: const Icon(Icons.check),
                        tooltip: 'library.tooltip_confirm'.tr(),
                      )
                    else
                      IconButton(
                        onPressed: _handleDeleteConfirm,
                        icon: const Icon(Icons.delete, color: Colors.red),
                        tooltip: 'library.tooltip_delete'.tr(),
                      ),
                    IconButton(
                      onPressed: _exitSelectionMode,
                      icon: const Icon(Icons.close),
                      tooltip: 'library.tooltip_cancel'.tr(),
                    ),
                  ],
                ],
              ),
            ),
            CategoryFilterBar(
              selected: _category,
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              onSelected: (value) {
                if (_category == value) return;
                setState(() {
                  _category = value;
                  _practiceVisibleCount = kFeedPageSize;
                });
              },
            ),
            TabBar(
              controller: _libraryTabs,
              labelColor: LoopiColors.deepPurple,
              unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
              indicatorColor: LoopiColors.deepPurple,
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: [
                Tab(text: 'library.tab_my_routines'.tr()),
                Tab(text: 'library.tab_favorites'.tr()),
                Tab(text: 'library.tab_practice'.tr()),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _libraryTabs,
                children: [
                  ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    children: [
                      if (groups.isEmpty && ungrouped.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('library.empty_category'.tr()),
                        ),
                      for (final group in groups)
                        _RoutineGroupCard(
                          group: group,
                          routines: widget.library.routinesForGroup(group).where(matchesRoutine).toList(),
                          isSelectionMode: _selectionMode != SelectionMode.none,
                          selectedIds: _selectedIds,
                          onToggleSelection: _toggleSelection,
                          onDeleteGroup: () async {
                            final shouldKeep = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: Text('library.delete_folder_title'.tr()),
                                content: Text('library.delete_folder_message'.tr()),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: Text('library.keep_originals'.tr()),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, false),
                                    child: Text('library.delete_routines_too'.tr()),
                                  ),
                                ],
                              ),
                            );
                            if (shouldKeep == null) return;
                            await widget.library.deleteGroup(group.id, keepRoutines: shouldKeep);
                          },
                          onPlayGroup: () {
                            final playlist = widget.library.routinesForGroup(group);
                            if (playlist.isEmpty) return;
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => PracticeModeScreen(
                                  library: widget.library,
                                  routine: playlist.first,
                                  routines: playlist,
                                  repeatPlaylist: true,
                                ),
                              ),
                            );
                          },
                          onOpenRoutine: widget.onStartRoutine,
                          onShareRoutine: widget.onShareRoutine,
                          onEditRoutine: widget.onEditRoutine,
                          onOpenRoutinePlayer: _openRoutinePlayer,
                          library: widget.library,
                        ),
                      if (ungrouped.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            'library.ungrouped'.tr(),
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        for (final routine in ungrouped)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RoutineCard(
                              routine: routine,
                              library: widget.library,
                              onStart: () => _openRoutinePlayer(routine),
                              onPractice: () => widget.onStartRoutine(routine),
                              onShare: () => widget.onShareRoutine(routine),
                              onFavorite: (value) => widget.onFavorite(routine, value),
                              onEdit: () => widget.onEditRoutine(routine),
                              isSelected: _selectedIds.contains(routine.id),
                              onTap: _selectionMode != SelectionMode.none
                                  ? () => _toggleSelection(routine.id)
                                  : null,
                            ),
                          ),
                      ],
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    children: [
                      if (favorites.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('library.empty_favorites'.tr()),
                        )
                      else
                        for (final routine in favorites)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _RoutineCard(
                              routine: routine,
                              library: widget.library,
                              onStart: () => widget.onOpenRoutinePlayer(routine),
                              onPractice: () => widget.onStartRoutine(routine),
                              onFavorite: (value) => widget.onFavorite(routine, value),
                              onEdit: () => widget.onEditRoutine(routine),
                            ),
                          ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                    children: [
                      if (practiceResults.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('library.empty_practice'.tr()),
                        )
                      else
                        for (final result in visiblePractice)
                          ListTile(
                            leading: _selectionMode != SelectionMode.none
                                ? Checkbox(
                                    value: _selectedIds.contains(result.id),
                                    onChanged: (value) {
                                      if (value == true) {
                                        _selectedIds.add(result.id);
                                      } else {
                                        _selectedIds.remove(result.id);
                                      }
                                      setState(() {});
                                    },
                                  )
                                : const Icon(Icons.video_library_outlined),
                            title: Text(result.name),
                            subtitle: Text('${'library.practice_record'.tr()} · ${result.createdAt.toLocal()}'),
                            trailing: _selectionMode == SelectionMode.none
                                ? IconButton(
                                    tooltip: 'library.tooltip_share'.tr(),
                                    icon: const Icon(Icons.share_outlined),
                                    onPressed: () => widget.onSharePracticeResult(result),
                                  )
                                : null,
                            onTap: () {
                              if (_selectionMode != SelectionMode.none) {
                                if (_selectedIds.contains(result.id)) {
                                  _selectedIds.remove(result.id);
                                } else {
                                  _selectedIds.add(result.id);
                                }
                                setState(() {});
                                return;
                              }
                              final routine = widget.library.byId(result.routineId);
                              if (routine == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('원본 루틴을 찾을 수 없어 재생할 수 없습니다.'),
                                  ),
                                );
                                return;
                              }
                              try {
                                widget.onOpenPracticeView(
                                  PracticeResultViewer(routine: routine, result: result),
                                );
                              } catch (error) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('재생 화면을 열 수 없습니다.\n$error')),
                                );
                              }
                            },
                          ),
                      if (practiceResults.length > visiblePractice.length)
                        TextButton(
                          onPressed: () => setState(() => _practiceVisibleCount += kFeedPageSize),
                          child: Text('community.load_more'.tr()),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RoutineGroupCard extends StatefulWidget {
  const _RoutineGroupCard({
    required this.group,
    required this.routines,
    required this.isSelectionMode,
    required this.selectedIds,
    required this.onToggleSelection,
    required this.onDeleteGroup,
    required this.onPlayGroup,
    required this.onOpenRoutine,
    required this.onShareRoutine,
    required this.onEditRoutine,
    required this.onOpenRoutinePlayer,
    required this.library,
  });

  final RoutineGroup group;
  final List<SavedRoutine> routines;
  final bool isSelectionMode;
  final Set<String> selectedIds;
  final void Function(String id) onToggleSelection;
  final Future<void> Function() onDeleteGroup;
  final VoidCallback onPlayGroup;
  final ValueChanged<SavedRoutine> onOpenRoutine;
  final ValueChanged<SavedRoutine> onShareRoutine;
  final ValueChanged<SavedRoutine> onEditRoutine;
  final ValueChanged<SavedRoutine> onOpenRoutinePlayer;
  final RoutineLibrary library;

  @override
  State<_RoutineGroupCard> createState() => _RoutineGroupCardState();
}

class _RoutineGroupCardState extends State<_RoutineGroupCard> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          initiallyExpanded: false,
          leading: Icon(Icons.folder_rounded, color: LoopiColors.purple),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  widget.group.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: LoopiColors.purple.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'library.routine_count'.tr(namedArgs: {'count': '${widget.routines.length}'}),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: widget.onPlayGroup,
                icon: const Icon(Icons.play_arrow_rounded),
                tooltip: 'library.play_folder'.tr(),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'delete') {
                    widget.onDeleteGroup();
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'delete', child: Text('library.delete_folder_title'.tr())),
                ],
              ),
            ],
          ),
          children: [
            if (widget.routines.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('library.empty_folder'.tr()),
              )
            else
              ...widget.routines.map(
                (routine) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _RoutineCard(
                      routine: routine,
                      library: widget.library,
                      onStart: () => widget.onOpenRoutinePlayer(routine),
                      onPractice: () => widget.onOpenRoutine(routine),
                      onShare: () => widget.onShareRoutine(routine),
                      onEdit: () => widget.onEditRoutine(routine),
                      isSelected: widget.selectedIds.contains(routine.id),
                      onTap: widget.isSelectionMode ? () => widget.onToggleSelection(routine.id) : null,
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

class CommunityFeedScreen extends StatelessWidget {
  const CommunityFeedScreen({super.key, required this.feed, required this.library, this.onPlay});

  final CommunityFeedStore feed;
  final RoutineLibrary library;
  final ValueChanged<SavedRoutine>? onPlay;

  void _play(BuildContext context, SavedRoutine routine) {
    if (onPlay != null) {
      onPlay!(routine);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RoutinePlayerScreen(routine: routine, library: library),
      ),
    );
  }

  void _openProfile(BuildContext context, CommunityPost post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UserProfileRoutinesScreen(
          authorId: post.authorId,
          authorName: post.authorName,
          feed: feed,
          library: library,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: feed,
      builder: (context, _) {
        if (feed.posts.isEmpty) {
          return Center(child: Text('community.empty_routines'.tr()));
        }
        return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              itemCount: feed.posts.length,
              itemBuilder: (_, index) {
                final post = feed.posts[index];
                final routine = library.byId(post.routine.id) ?? post.routine;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    onTap: () => _play(context, routine),
                    leading: IconButton(
                      onPressed: () => _play(context, routine),
                      tooltip: 'player.play'.tr(),
                      icon: const Icon(Icons.play_circle_fill, size: 34),
                    ),
                    title: Text(routine.name),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextButton(
                          onPressed: () => _openProfile(context, post),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero),
                          child: Text('@${post.authorName}'),
                        ),
                        Text(post.description.isEmpty ? 'community.no_description'.tr() : post.description),
                      ],
                    ),
                    trailing: FavoriteButton(
                      initialValue: routine.isFavorite,
                      onChanged: (value) => feed.toggleFavorite(routine, value, library, context),
                    ),
                  ),
                );
              },
        );
      },
    );
  }
}

class UserProfileRoutinesScreen extends StatelessWidget {
  const UserProfileRoutinesScreen({
    super.key,
    required this.authorId,
    required this.authorName,
    required this.feed,
    required this.library,
  });

  final String authorId;
  final String authorName;
  final CommunityFeedStore feed;
  final RoutineLibrary library;

  @override
  Widget build(BuildContext context) {
    final posts = feed.posts.where((post) => post.authorId == authorId).toList();
    return Scaffold(
      appBar: AppBar(title: Text('@$authorName')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: posts.length,
        itemBuilder: (context, index) {
          final post = posts[index];
          final routine = library.byId(post.routine.id) ?? post.routine;
          return ListTile(
            leading: const Icon(Icons.play_circle_outline),
            title: Text(routine.name),
            subtitle: Text(post.description),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RoutinePlayerScreen(routine: routine, library: library),
              ),
            ),
          );
        },
      ),
    );
  }
}

