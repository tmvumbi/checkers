import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Uses Apple's own artwork, typography and accessibility on iOS/iPadOS.
class AppleSignInButton extends StatefulWidget {
  const AppleSignInButton({
    required this.onPressed,
    required this.fallbackLabel,
    super.key,
  });

  final VoidCallback? onPressed;
  final String fallbackLabel;

  @override
  State<AppleSignInButton> createState() => _AppleSignInButtonState();
}

class _AppleSignInButtonState extends State<AppleSignInButton> {
  MethodChannel? _channel;

  Future<void> _onPlatformViewCreated(int id) async {
    final channel = MethodChannel('cd.dame/apple-sign-in-button/$id');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (mounted && call.method == 'onPressed') {
        widget.onPressed?.call();
      }
    });
    await channel.invokeMethod<void>('setEnabled', widget.onPressed != null);
  }

  @override
  void didUpdateWidget(covariant AppleSignInButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.onPressed != null) != (widget.onPressed != null)) {
      _channel?.invokeMethod<void>('setEnabled', widget.onPressed != null);
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return SizedBox(
        height: 64,
        child: UiKitView(
          viewType: 'cd.dame/apple-sign-in-button',
          creationParams: {'enabled': widget.onPressed != null},
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        ),
      );
    }
    return SignInWithAppleButton(
      onPressed: widget.onPressed,
      text: widget.fallbackLabel,
      height: 64,
      style: SignInWithAppleButtonStyle.white,
    );
  }
}
