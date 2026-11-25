import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_state.dart';
import '../config.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../util/format.dart';
import '../widgets/common.dart';

/// Opens "Add a round" over the current screen: what the "+" on the tab bar
/// does.
Future<void> showAddRoundSheet(BuildContext context, AppState state) =>
    showAppSheet<void>(context, builder: (_) => AddRoundSheet(state: state));

/// "Add a round": the two ways a round gets onto this device's Home, and
/// nothing else.
///   "Start a round"        closes the sheet and opens the new-round screen
///                          (`/new`).
///   "Open an invite link"  swaps the sheet to [OpenLinkForm].
class AddRoundSheet extends StatefulWidget {
  const AddRoundSheet({super.key, required this.state});
  final AppState state;

  @override
  State<AddRoundSheet> createState() => _AddRoundSheetState();
}

class _AddRoundSheetState extends State<AddRoundSheet> {
  /// The sheet shows the link form instead of the two rows.
  bool _pasting = false;

  void _start() {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop();
    // Pushed, so "Back" on the new-round screen returns to where the person
    // was.
    router?.push('/new');
  }

  void _opened() {
    final router = GoRouter.maybeOf(context);
    Navigator.of(context).pop();
    router?.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return SheetFrame(
      tall: false,
      // The darker palette: the rows' quiet sentences keep their contrast.
      palette: AuroraPalette.ink,
      child: _pasting
          ? OpenLinkForm(state: widget.state, onOpened: _opened)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  child: Text('Add a round', style: t.title(30)),
                ),
                const SizedBox(height: Space.s4),
                GlassCard(
                  padding: EdgeInsets.zero,
                  radius: Radii.row,
                  child: ActionRow(
                    key: const Key('add-start'),
                    icon: Icons.bolt_rounded,
                    title: 'Start a round',
                    detail: 'Set the deposit and the goal, then invite people.',
                    minHeight: 76,
                    onPressed: _start,
                  ),
                ),
                const SizedBox(height: Space.s3),
                GlassCard(
                  padding: EdgeInsets.zero,
                  radius: Radii.row,
                  child: ActionRow(
                    key: const Key('add-link'),
                    icon: Icons.link_rounded,
                    title: 'Open an invite link',
                    detail: 'Paste a link someone sent you.',
                    minHeight: 76,
                    onPressed: () => setState(() => _pasting = true),
                  ),
                ),
              ],
            ),
    );
  }
}

/// "Open an invite link": paste a round's link (or its address) to put that
/// round on this device's Home, listed or not. A link opened in a browser
/// does this by itself; this is the way in for a phone build.
///
/// When the round is open and selected it says "Round opened." and calls
/// [onOpened]: the sheet closes and the app goes Home.
class OpenLinkForm extends StatefulWidget {
  const OpenLinkForm({super.key, required this.state, this.onOpened});
  final AppState state;
  final VoidCallback? onOpened;

  @override
  State<OpenLinkForm> createState() => _OpenLinkFormState();
}

class _OpenLinkFormState extends State<OpenLinkForm> {
  final _link = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // The sheet has one field: the cursor starts in it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _link.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final state = widget.state;
    final launcher = AppConfig.launcherFromLink(_link.text);
    if (launcher == null) {
      setState(
        () => _error =
            'That isn\'t a round link. Paste the whole link, or the '
            'round\'s address.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await state.openLink(launcher);
      if (!mounted) return;
      if (state.selected == launcher) {
        _link.clear();
        showMessage(context, 'Round opened.', kind: BannerKind.success);
        widget.onOpened?.call();
      } else {
        // The state says why in one sentence; it is shown here instead.
        final said = state.notice;
        state.notice = null;
        setState(
          () => _error =
              said ??
              state.roundError ??
              'That round could not be opened. Try again.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    return PopScope(
      canPop: !_busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Open an invite link', style: t.title(30)),
          ),
          const SizedBox(height: Space.s4),
          const Overline('Invite link'),
          const SizedBox(height: 10),
          GlassField(
            fieldKey: const Key('open-round'),
            controller: _link,
            focusNode: _focus,
            placeholder: 'Paste the link',
            label: 'Invite link',
            mono: true,
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: Space.s5),
          if (_error != null) ...[
            ErrorLine(_error!),
            const SizedBox(height: Space.s3),
          ],
          PillButton(
            icon: Icons.link_rounded,
            label: 'Open round',
            busy: _busy,
            busyLabel: 'Opening the round…',
            onPressed: _link.text.trim().isEmpty ? null : _open,
          ),
        ],
      ),
    );
  }
}
