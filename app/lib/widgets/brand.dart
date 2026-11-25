import 'package:flutter/material.dart';

import '../theme/theme.dart';
import '../theme/tokens.dart';

/// "Built on Flap": plain words, with Flap's official logo beside them when
/// the asset is in the build (assets/brand/flap.png, see the README next to
/// it for where it comes from and how it may be used). The logo is shown
/// once, small, unchanged, with clear space around it. If the file is
/// missing the words stand alone.
class FlapAttribution extends StatelessWidget {
  const FlapAttribution({super.key});

  /// The single brand slot.
  static const asset = 'assets/brand/flap.png';

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Built on Flap',
    child: ExcludeSemantics(
      child: Row(
        children: [
          Text('Built on Flap', style: context.type.body(16, FontWeight.w600)),
          const SizedBox(width: Space.s4),
          // The file carries its own transparent margin: at 32px the logo
          // itself is about 19px tall, close to the text beside it. The kit
          // asks that the logo is not oversized; our own floor is 16px.
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Image.asset(
                asset,
                height: 32,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
