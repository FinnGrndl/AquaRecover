import 'package:flutter/cupertino.dart';

/// The deep-water gradient behind AquaRecover's start and library screens.
class OceanBackdrop extends StatelessWidget {
  const OceanBackdrop({super.key, required this.child});

  static const base = Color(0xff041923);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff07384b), Color(0xff07596b), Color(0xff03151e)],
          stops: [0, .50, 1],
        ),
      ),
      child: child,
    );
  }
}
