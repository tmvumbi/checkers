import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../data/models/online_game.dart';
import '../../../../services/online_game_service.dart';
import '../../../../shared/widgets/checkers_modal.dart';
import '../../../../themes/app_theme.dart';
import '../../../../translations/translation_keys.dart';
import '../../controller/game_board_controller.dart';

const int _maxAvatars = 5;

/// Live row of overlapping spectator avatars (max [_maxAvatars], then a
/// "+X" bubble). Tapping opens the paginated watchers modal.
class WatchersBar extends GetView<GameBoardController> {
  const WatchersBar({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      final watchers = controller.watchers;
      if (watchers.isEmpty) {
        return const SizedBox(height: 4);
      }
      final visible = watchers.take(_maxAvatars).toList();
      final overflow = watchers.length - visible.length;
      final bubbleCount = visible.length + (overflow > 0 ? 1 : 0);
      const diameter = 28.0;
      const step = 20.0;

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: Row(
          children: [
            Icon(
              Icons.visibility_outlined,
              size: 16,
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            InkWell(
              key: const Key('watchers-bar'),
              onTap: () => _showWatchersModal(context),
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: diameter,
                width: step * (bubbleCount - 1) + diameter,
                child: Stack(
                  children: [
                    for (var i = 0; i < visible.length; i++)
                      Positioned(
                        left: i * step,
                        child: _WatcherAvatar(
                          watcher: visible[i],
                          diameter: diameter,
                          theme: theme,
                        ),
                      ),
                    if (overflow > 0)
                      Positioned(
                        left: visible.length * step,
                        child: _OverflowBubble(
                          count: overflow,
                          diameter: diameter,
                          theme: theme,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  void _showWatchersModal(BuildContext context) {
    final gameId = controller.watchableGameId;
    if (gameId == null) {
      return;
    }
    showCheckersModal<void>(
      context: context,
      builder: (dialogContext) => _WatchersModalContent(gameId: gameId),
    );
  }
}

class _WatcherAvatar extends StatelessWidget {
  const _WatcherAvatar({
    required this.watcher,
    required this.diameter,
    required this.theme,
  });

  final GameWatcher watcher;
  final double diameter;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.shadow.withValues(alpha: 0.8),
        border: Border.all(color: theme.colorScheme.onPrimary, width: 1.5),
        image: watcher.photoUrl == null
            ? null
            : DecorationImage(
                image: NetworkImage(watcher.photoUrl!),
                fit: BoxFit.cover,
              ),
      ),
      child: watcher.photoUrl == null
          ? Icon(
              Icons.person,
              size: diameter * 0.6,
              color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
            )
          : null,
    );
  }
}

class _OverflowBubble extends StatelessWidget {
  const _OverflowBubble({
    required this.count,
    required this.diameter,
    required this.theme,
  });

  final int count;
  final double diameter;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final brand = theme.extension<CheckersThemeExtension>()!;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.shadow.withValues(alpha: 0.9),
        border: Border.all(color: brand.brandGold, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '+$count',
        key: const Key('watchers-overflow'),
        style: theme.textTheme.bodyLarge!.copyWith(
          color: brand.brandGold,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _WatchersModalContent extends StatefulWidget {
  const _WatchersModalContent({required this.gameId});

  final String gameId;

  @override
  State<_WatchersModalContent> createState() => _WatchersModalContentState();
}

class _WatchersModalContentState extends State<_WatchersModalContent> {
  static const int _pageSize = 20;

  final List<GameWatcher> _watchers = [];
  bool _loading = true;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    setState(() => _loading = true);
    final OnlineGameService service = Get.find();
    final result = await service.fetchWatchers(
      widget.gameId,
      offset: _watchers.length,
      limit: _pageSize,
    );
    if (!mounted) {
      return;
    }
    result.when(
      success: (page) {
        setState(() {
          _watchers.addAll(page);
          _hasMore = page.length == _pageSize;
          _loading = false;
        });
      },
      failure: (_) => setState(() => _loading = false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brand = theme.extension<CheckersThemeExtension>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckersModalHeader(
          title: TranslationKeys.watchersTitle.tr,
          closeKey: const Key('watchers-close'),
          onClose: () => Navigator.of(context).pop(),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _watchers.length + (_hasMore || _loading ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= _watchers.length) {
                if (_loading) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: brand.brandGold,
                        ),
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton(
                    key: const Key('watchers-load-more'),
                    onPressed: _loadMore,
                    child: Text(
                      TranslationKeys.loadMore.tr,
                      style: TextStyle(
                        color: brand.brandGold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }
              final watcher = _watchers[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    _WatcherAvatar(
                      watcher: watcher,
                      diameter: 34,
                      theme: theme,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        watcher.nickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge!.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      '${watcher.rating}',
                      style: theme.textTheme.bodyLarge!.copyWith(
                        color: brand.brandGold,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
