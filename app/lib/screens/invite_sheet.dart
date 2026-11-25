import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_state.dart';
import '../config.dart';
import '../services/verifier_api.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// What the invite sheet and the new-round screen say about a round
/// that is not in the public list. Exactly this: it is not hidden.
const unlistedNote =
    'Not shown in the public list. Anyone with the link can still join, and '
    'the chain is public.';

/// Opens "Invite" for [round]: its link, a copy button and a QR code.
Future<void> showInviteSheet(
  BuildContext context,
  AppState state,
  Round round,
) => showAppSheet<void>(
  context,
  builder: (_) => InviteSheet(state: state, round: round),
);

/// The body of the invite sheet. The link is
/// `<webBaseUrl>/#/r/<launcher>`: opening it selects the round, listed or
/// not. A build with no web address hands out the round's address instead.
///
/// On the device that started the round, the sheet also holds the
/// "Unlisted" switch: the creator can change it at any time.
class InviteSheet extends StatefulWidget {
  const InviteSheet({
    super.key,
    required this.state,
    required this.round,
    this.link,
  });
  final AppState state;
  final Round round;

  /// Defaults to [AppConfig.inviteLink]; a parameter so tests can show both
  /// cases.
  final String? link;

  @override
  State<InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<InviteSheet> {
  bool _busy = false;
  String? _error;

  AppState get _state => widget.state;

  Future<void> _setUnlisted(bool unlisted) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _state.registerRound(widget.round.launcher, unlisted: unlisted);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _state,
    builder: (context, _) {
      final t = context.type;
      final c = context.colors;
      final round = widget.round;
      final link = widget.link ?? AppConfig.inviteLink(round.launcher);
      final hasLink = link.isNotEmpty;
      final shared = hasLink ? link : round.id;
      final known = _state.knownRound(round.launcher);
      final mine =
          _state.hasWallet && known?.creator == _state.address.toLowerCase();
      final unlisted = mine
          ? known?.unlisted ?? round.unlisted
          : _state.rounds
                .firstWhere((r) => r.id == round.id, orElse: () => round)
                .unlisted;

      return SheetFrame(
        tall: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Overline('Invite'),
            const SizedBox(height: Space.s1),
            Semantics(
              header: true,
              child: Text(
                round.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: t.title(30),
              ),
            ),
            const SizedBox(height: Space.s2),
            Text(
              unlisted && !mine
                  ? unlistedNote
                  : 'Anyone with this link can open the round and join.',
              style: t.body(15).copyWith(color: c.text2),
            ),
            const SizedBox(height: Space.s5),
            if (hasLink) ...[
              Center(
                child: Semantics(
                  image: true,
                  label: 'QR code of the invite link',
                  excludeSemantics: true,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: QrImageView(
                      key: const Key('invite-qr'),
                      data: link,
                      size: 196,
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Space.s5),
            ] else ...[
              Text(
                'This build has no web address, so there is no link to hand '
                'out. Share the round\'s address instead: it opens under '
                '"Open an invite link", behind the + on the tab bar.',
                style: t.body(13).copyWith(color: c.text2),
              ),
              const SizedBox(height: Space.s3),
            ],
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: SelectableText(
                shared,
                key: const Key('invite-link'),
                style: t.mono.copyWith(fontSize: 12.5),
              ),
            ),
            const SizedBox(height: Space.s4),
            PillButton(
              icon: Icons.copy_rounded,
              label: hasLink ? 'Copy link' : 'Copy round address',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shared));
                showMessage(
                  context,
                  hasLink ? 'Invite link copied.' : 'Round address copied.',
                );
              },
            ),
            if (mine) ...[
              const SizedBox(height: Space.s4),
              GlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Opacity(
                  opacity: _busy ? 0.5 : 1,
                  child: CapsuleToggle(
                    key: const Key('invite-unlisted'),
                    title: 'Unlisted',
                    detail: unlistedNote,
                    value: unlisted,
                    onChanged: _setUnlisted,
                  ),
                ),
              ),
              if (_error != null || !(known?.registered ?? true) && !_busy) ...[
                const SizedBox(height: Space.s3),
                ErrorLine(
                  _error ??
                      known?.registerError ??
                      'The server has not saved this yet.',
                ),
              ],
            ],
          ],
        ),
      );
    },
  );
}
