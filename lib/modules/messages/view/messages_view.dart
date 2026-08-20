import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:get/get.dart';

import '../../../data/models/player_message.dart';
import '../../../routes/app_routes.dart';
import '../../../shared/widgets/checkers_ad_banner.dart';
import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_square_icon_button.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';
import '../controller/messages_controller.dart';

class MessagesView extends GetView<MessagesController> {
  const MessagesView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandTheme = theme.extension<CheckersThemeExtension>()!;

    return Scaffold(
      body: CheckersBackground(
        // The scroll view shrink-wraps, so force the backdrop full-screen.
        child: SizedBox.expand(
          child: SafeArea(
            child: Column(
              children: [
                const CheckersAdBanner(
                  key: Key('messages-ad-banner'),
                  size: CheckersAdBannerSize.compactAdaptive,
                ),
                Expanded(
                  child: Obx(() {
                    final messages = controller.messages.toList(
                      growable: false,
                    );
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 430),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      TranslationKeys.messagesTitle.tr,
                                      style: theme.textTheme.headlineMedium!
                                          .copyWith(
                                            color: brandTheme.brandGold,
                                            fontSize: 32,
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                  ),
                                  CheckersSquareIconButton(
                                    key: const Key('messages-close-button'),
                                    dimension: 48,
                                    icon: Icons.close,
                                    iconSize: 26,
                                    onPressed: () => Get.back<void>(),
                                    tooltip: TranslationKeys.close.tr,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 24),
                              if (messages.isEmpty)
                                _MessagesEmptyState(theme: theme)
                              else
                                for (final message in messages)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: _PlayerMessageCard(message: message),
                                  ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessagesEmptyState extends StatelessWidget {
  const _MessagesEmptyState({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 56),
      child: Text(
        TranslationKeys.messagesEmpty.tr,
        key: const Key('messages-empty'),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge!.copyWith(
          color: theme.colorScheme.onPrimary,
          fontSize: 18,
          height: 1.35,
        ),
      ),
    );
  }
}

class _PlayerMessageCard extends StatelessWidget {
  const _PlayerMessageCard({required this.message});

  final PlayerMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandTheme = theme.extension<CheckersThemeExtension>()!;
    final borderRadius = BorderRadius.circular(8);

    final content = Container(
      key: Key('player-message-${message.id}'),
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.shadow.withValues(alpha: 0.3),
        borderRadius: borderRadius,
        border: Border.all(
          color: theme.colorScheme.onPrimary.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message.hasText)
            Html(
              data: message.htmlText,
              style: {
                'body': Style(
                  color: theme.colorScheme.onPrimary,
                  fontSize: FontSize(16),
                  lineHeight: const LineHeight(1.35),
                  margin: Margins.zero,
                  padding: HtmlPaddings.zero,
                ),
                'a': Style(color: brandTheme.brandGold),
              },
            ),
          if (message.hasText && message.hasImage) const SizedBox(height: 12),
          if (message.hasImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                message.imageUrl!,
                key: Key('player-message-image-${message.id}'),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.28),
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );

    if (!message.hasLink) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: borderRadius,
        onTap: () {
          Get.toNamed<void>(AppRoutes.messageLink, arguments: message.linkUrl);
        },
        child: content,
      ),
    );
  }
}
