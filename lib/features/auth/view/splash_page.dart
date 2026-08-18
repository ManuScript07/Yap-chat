import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yap_chat/core/core.dart';

@RoutePage()
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  static const _nativeSplashCanvasSize = 288.0;
  static const _logoScale = 0.86624205;

  var _isProgressVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isProgressVisible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.primary,
      body: Center(
        child: SizedBox(
          width: _nativeSplashCanvasSize,
          height: _nativeSplashCanvasSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: _logoScale,
                child: SvgPicture.asset(
                  'assets/logo/icon_yapchat_foregraund.svg',
                  width: 157,
                  height: 137,
                ),
              ),
              Positioned(
                top: 218,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    opacity: _isProgressVisible ? 1 : 0,
                    child: CircularProgressIndicator(
                      color: context.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
