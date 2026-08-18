import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yap_chat/app/app_config.dart';
import 'package:yap_chat/core/core.dart';
import 'package:yap_chat/features/auth/auth.dart';
import 'package:yap_chat/ui/ui.dart';

@RoutePage()
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: (previous, current) =>
          previous.failure != current.failure && current.failure != null,
      listener: (context, state) {
        showAppSnackBar(
          context,
          message: context.l10n.authSignInFailed,
          type: SnackBarType.error,
        );
        context.read<AuthBloc>().add(const AuthFailureCleared());
      },
      child: Scaffold(
        backgroundColor: context.colorScheme.primary,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape =
                constraints.maxWidth >= 600 &&
                constraints.maxWidth > constraints.maxHeight;

            return isLandscape
                ? _WelcomeLandscapeLayout(constraints: constraints)
                : _WelcomePortraitLayout(constraints: constraints);
          },
        ),
      ),
    );
  }
}

class _WelcomePortraitLayout extends StatelessWidget {
  const _WelcomePortraitLayout({required this.constraints});

  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final panelHeight = math.min(288.0, constraints.maxHeight * 0.42);

    return Column(
      children: [
        SafeArea(
          bottom: false,
          child: _WelcomeTitle(
            topPadding: math.min(64.0, constraints.maxHeight * 0.075),
            maxWidth: constraints.maxWidth,
          ),
        ),
        Expanded(
          child: _WelcomeLogo(
            maxWidth: constraints.maxWidth,
            allowHorizontalOverflow: true,
          ),
        ),
        _WelcomeAuthPanel(height: panelHeight),
      ],
    );
  }
}

class _WelcomeLandscapeLayout extends StatelessWidget {
  const _WelcomeLandscapeLayout({required this.constraints});

  final BoxConstraints constraints;

  @override
  Widget build(BuildContext context) {
    final panelWidth = math.min(400.0, constraints.maxWidth * 0.43);
    final panelHeight = math.min(288.0, constraints.maxHeight - 32);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  _WelcomeTitle(
                    topPadding: 16,
                    maxWidth: constraints.maxWidth - panelWidth,
                  ),
                  Expanded(
                    child: _WelcomeLogo(
                      maxWidth: constraints.maxWidth - panelWidth,
                      allowHorizontalOverflow: false,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: panelWidth,
              child: Center(
                child: _WelcomeAuthPanel(
                  height: panelHeight,
                  isSidePanel: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeTitle extends StatelessWidget {
  const _WelcomeTitle({required this.topPadding, required this.maxWidth});

  final double topPadding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: topPadding),
      child: SizedBox(
        width: math.min(295, math.max(0, maxWidth - 32)),
        height: 20,
        child: Text(
          context.l10n.authWelcomeTitle,
          textAlign: TextAlign.center,
          maxLines: 1,
          style: context.textTheme.headlineMedium?.copyWith(
            color: context.colorScheme.onPrimary,
            fontSize: 32,
            fontWeight: FontWeight.w700,
            height: 0.63,
            letterSpacing: 0.32,
          ),
        ),
      ),
    );
  }
}

class _WelcomeLogo extends StatelessWidget {
  const _WelcomeLogo({
    required this.maxWidth,
    required this.allowHorizontalOverflow,
  });

  final double maxWidth;
  final bool allowHorizontalOverflow;

  @override
  Widget build(BuildContext context) {
    final logoWidth = maxWidth * (allowHorizontalOverflow ? 456 / 412 : 0.82);

    return Center(
      child: ClipRect(
        child: OverflowBox(
          minWidth: logoWidth,
          maxWidth: logoWidth,
          alignment: Alignment.center,
          child: SvgPicture.asset(
            'assets/logo/welcome_big_logo.svg',
            width: logoWidth,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

class _WelcomeAuthPanel extends StatelessWidget {
  const _WelcomeAuthPanel({required this.height, this.isSidePanel = false});

  final double height;
  final bool isSidePanel;

  @override
  Widget build(BuildContext context) {
    final panelRadius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(isSidePanel ? 20 : 18),
      bottomRight: Radius.circular(isSidePanel ? 20 : 18),
    );

    return SizedBox(
      width: double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.scaffoldBackgroundColor,
          borderRadius: panelRadius,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelHeight = constraints.maxHeight;
            final panelWidth = constraints.maxWidth;
            final buttonWidth = math.min(247.0, panelWidth * 0.72);

            return Stack(
              children: [
                Positioned(
                  top: panelHeight * (32 / 288),
                  left: 16,
                  right: 16,
                  child: Text(
                    context.l10n.authSignInWith,
                    textAlign: TextAlign.center,
                    style: context.textTheme.titleLarge?.copyWith(
                      color: context.colorScheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w500,
                      height: 0.91,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                Positioned(
                  top: panelHeight * (115 / 288),
                  left: 0,
                  right: 0,
                  child: Center(child: _YandexSignInButton(width: buttonWidth)),
                ),
                Positioned(
                  top: panelHeight * (208 / 288),
                  left: math.min(31, panelWidth * 0.075),
                  right: math.min(31, panelWidth * 0.075),
                  child: const _AuthConsentText(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _YandexSignInButton extends StatelessWidget {
  const _YandexSignInButton({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      buildWhen: (previous, current) =>
          previous.isSubmitting != current.isSubmitting,
      builder: (context, state) {
        return SizedBox(
          width: width,
          height: 57,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: context.colorScheme.primary,
              foregroundColor: context.colorScheme.onPrimary,
              padding: EdgeInsets.zero,
              shape: const StadiumBorder(),
            ),
            onPressed: state.isSubmitting
                ? null
                : () => context.read<AuthBloc>().add(
                    const YandexSignInRequested(),
                  ),
            child: state.isSubmitting
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.colorScheme.onPrimary,
                    ),
                  )
                : SvgPicture.asset(
                    'assets/logo/yandex-id-seeklogo.svg',
                    width: math.min(176, width - 32),
                    height: 32,
                  ),
          ),
        );
      },
    );
  }
}

class _AuthConsentText extends StatefulWidget {
  const _AuthConsentText();

  @override
  State<_AuthConsentText> createState() => _AuthConsentTextState();
}

class _AuthConsentTextState extends State<_AuthConsentText> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument('TERMS_OF_SERVICE_URL');
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _openDocument('PRIVACY_POLICY_URL');
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = context.textTheme.bodySmall?.copyWith(
      color: context.colorScheme.onSurface,
      fontSize: 13,
      height: 1.23,
      letterSpacing: 0.1,
    );
    final linkStyle = textStyle?.copyWith(
      decoration: TextDecoration.underline,
      decorationColor: context.colorScheme.onSurface,
    );

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${context.l10n.authConsentPrefix} ',
            style: textStyle,
          ),
          TextSpan(
            text: context.l10n.authTermsOfService,
            style: linkStyle,
            recognizer: _termsRecognizer,
          ),
          TextSpan(
            text: ' ${context.l10n.authDocumentsAnd} ',
            style: textStyle,
          ),
          TextSpan(
            text: context.l10n.authPrivacyPolicy,
            style: linkStyle,
            recognizer: _privacyRecognizer,
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Future<void> _openDocument(String envKey) async {
    final rawUrl = context.read<AppConfig>().env[envKey];
    final url = rawUrl == null ? null : Uri.tryParse(rawUrl);
    if (url != null) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }
}
