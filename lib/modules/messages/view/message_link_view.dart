import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../shared/widgets/checkers_background.dart';
import '../../../shared/widgets/checkers_square_icon_button.dart';
import '../../../themes/app_theme.dart';
import '../../../translations/translation_keys.dart';

/// In-app browser for a player message's link (kopo parity).
class MessageLinkView extends StatefulWidget {
  const MessageLinkView({super.key});

  @override
  State<MessageLinkView> createState() => _MessageLinkViewState();
}

class _MessageLinkViewState extends State<MessageLinkView> {
  WebViewController? _webViewController;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    final url = Get.arguments as String?;
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _hasError = true;
      _isLoading = false;
      return;
    }

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _hasError = false;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (_) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _hasError = true;
              });
            }
          },
        ),
      )
      ..loadRequest(uri);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brandTheme = theme.extension<CheckersThemeExtension>()!;
    final webViewController = _webViewController;

    return Scaffold(
      body: CheckersBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: CheckersSquareIconButton(
                    key: const Key('message-link-close-button'),
                    dimension: 48,
                    icon: Icons.close,
                    iconSize: 26,
                    onPressed: () => Get.back<void>(),
                    tooltip: TranslationKeys.close.tr,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColoredBox(
                      color: theme.colorScheme.surface,
                      child: Stack(
                        children: [
                          if (webViewController != null)
                            Positioned.fill(
                              child: WebViewWidget(
                                controller: webViewController,
                              ),
                            ),
                          if (_isLoading)
                            Center(
                              child: CircularProgressIndicator(
                                color: brandTheme.brandGold,
                              ),
                            ),
                          if (_hasError)
                            ColoredBox(
                              color: theme.colorScheme.shadow.withValues(
                                alpha: 0.72,
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    TranslationKeys.messageLinkLoadError.tr,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.bodyLarge!.copyWith(
                                      color: theme.colorScheme.onPrimary,
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
