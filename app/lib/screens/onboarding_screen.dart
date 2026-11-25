import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../theme/theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Shown once, before anything else. Two steps:
///   1. what this is: a hero line, one sentence, one button;
///   2. connect Apple Health / Health Connect (in a browser: a note that the
///      check-in there is self-reported).
/// The wallet is made between the two with nothing shown, and the faucet is
/// asked for gas in the background.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.state});
  final AppState state;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _busy = false;

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await widget.state.createWallet();
      if (!mounted) return;
      setAuroraTone(AuroraPalette.steel);
      setState(() => _step = 1);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finish({required bool ask}) async {
    setState(() => _busy = true);
    try {
      if (ask) {
        try {
          await widget.state.health.requestAccess();
        } catch (_) {
          // The check-in asks again when it needs the steps.
        }
      }
      await widget.state.completeOnboarding();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    setAuroraTone(AuroraPalette.ink);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: AnimatedSwitcher(
      duration: context.motion
          ? const Duration(milliseconds: 400)
          : Duration.zero,
      child: _step == 0
          ? _Welcome(key: const ValueKey(0), busy: _busy, onStart: _start)
          : _HealthStep(
              key: const ValueKey(1),
              busy: _busy,
              available: widget.state.health.available,
              onAllow: () => _finish(ask: true),
              onSkip: () => _finish(ask: false),
            ),
    ),
  );
}

/// A column that fills the screen and scrolls when the screen is too short
/// for it.
class _FillScroll extends StatelessWidget {
  const _FillScroll({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ),
      ),
    ),
  );
}

class _Welcome extends StatefulWidget {
  const _Welcome({super.key, required this.busy, required this.onStart});
  final bool busy;
  final VoidCallback onStart;

  @override
  State<_Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<_Welcome>
    with SingleTickerProviderStateMixin {
  late final _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!context.motion) {
      _enter.value = 1;
    } else if (_enter.status == AnimationStatus.dismissed) {
      _enter.forward();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final shown = CurvedAnimation(parent: _enter, curve: Curves.easeOut);
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: shown,
            child: const Center(
              child: OverflowBox(
                maxHeight: double.infinity,
                maxWidth: double.infinity,
                child: Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: TrackHero(),
                ),
              ),
            ),
          ),
        ),
        _FillScroll(
          children: [
            const SizedBox(height: Space.s3),
            const Wordmark(AppConfig.productName),
            const Spacer(),
            const SizedBox(height: Space.s12),
            FadeTransition(
              opacity: shown,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.15),
                  end: Offset.zero,
                ).animate(shown),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Semantics(
                    header: true,
                    child: Text(AppConfig.heroLine, style: t.display(78)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FadeTransition(
              opacity: shown,
              child: Text(
                'Pay a deposit, check in every day you move, and share the '
                'prize and a new token with everyone who showed up.',
                style: t.body(16).copyWith(color: c.text2),
              ),
            ),
            const SizedBox(height: Space.s8),
            PillButton(
              label: 'Get started',
              busy: widget.busy,
              busyLabel: 'One moment…',
              onPressed: widget.onStart,
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                'BNB Smart Chain testnet. Nothing here has real value.',
                textAlign: TextAlign.center,
                style: t.body(12).copyWith(color: c.text2),
              ),
            ),
            const SizedBox(height: Space.s3),
          ],
        ),
      ],
    );
  }
}

class _HealthStep extends StatefulWidget {
  const _HealthStep({
    super.key,
    required this.busy,
    required this.available,
    required this.onAllow,
    required this.onSkip,
  });

  final bool busy;

  /// There is a health store to read (a phone build).
  final bool available;
  final VoidCallback onAllow;
  final VoidCallback onSkip;

  @override
  State<_HealthStep> createState() => _HealthStepState();
}

class _HealthStepState extends State<_HealthStep>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!context.motion) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    final ios = defaultTargetPlatform == TargetPlatform.iOS;
    final store = ios ? 'Apple Health' : 'Health Connect';
    final phone = widget.available;
    return _FillScroll(
      children: [
        const Spacer(),
        const SizedBox(height: Space.s5),
        Center(
          child: SizedBox(
            width: 220,
            height: 190,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < 3; i++)
                  ScaleTransition(
                    scale: Tween(begin: 0.96, end: 1.06).animate(
                      CurvedAnimation(
                        parent: _pulse,
                        curve: Interval(i * 0.12, 1, curve: Curves.easeInOut),
                      ),
                    ),
                    child: Container(
                      width: 116 + i * 52,
                      height: 116 + i * 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(
                            alpha: 0.10 - i * 0.03,
                          ),
                        ),
                      ),
                    ),
                  ),
                GlassSurface.pill(
                  tint: c.volt,
                  child: SizedBox(
                    width: 100,
                    height: 100,
                    child: Icon(
                      phone
                          ? Icons.monitor_heart_rounded
                          : Icons.edit_note_rounded,
                      size: 46,
                      color: c.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.s8),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Semantics(
            header: true,
            child: Text(
              phone
                  ? 'CONNECT\n${store.toUpperCase()}'
                  : 'CHECK IN\nIN THE BROWSER',
              style: t.display(54),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          phone
              ? 'Your steps are how you check in. ${AppConfig.productName} '
                    'reads today\'s count each time you check in.'
              : 'A browser cannot read health data, so the check-in here is '
                    'a step count you type yourself: self-reported, for the '
                    'testnet demo.',
          style: t.body(16).copyWith(color: c.text2),
        ),
        const SizedBox(height: Space.s6),
        if (phone) ...[
          const _PermissionRow(
            icon: Icons.directions_walk_rounded,
            title: 'Steps today',
            detail: 'Recorded by a device. Typed entries are left out.',
          ),
          const SizedBox(height: 10),
          const _PermissionRow(
            icon: Icons.visibility_outlined,
            title: 'Read only',
            detail: 'Nothing is ever written to your health data.',
          ),
        ] else ...[
          const _PermissionRow(
            icon: Icons.edit_outlined,
            title: 'You type today\'s steps',
            detail: 'Self-reported, testnet only.',
          ),
          const SizedBox(height: 10),
          const _PermissionRow(
            icon: Icons.phone_iphone_rounded,
            title: 'On the phone app',
            detail: 'Steps come from Apple Health or Health Connect.',
          ),
        ],
        const SizedBox(height: 10),
        const _PermissionRow(
          icon: Icons.verified_user_outlined,
          title: 'Our server signs the day',
          detail: 'Check-ins are attested, not proven.',
        ),
        const SizedBox(height: Space.s3),
        Row(
          children: [
            Icon(Icons.lock_outline_rounded, size: 16, color: c.text2),
            const SizedBox(width: Space.s2),
            Expanded(
              child: Text(
                'Your step count goes to our server. Only the day you '
                'checked in goes on chain.',
                style: t.body(12, FontWeight.w500).copyWith(color: c.text2),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.s5),
        PillButton(
          label: phone ? 'Allow access' : 'Continue',
          icon: phone ? Icons.favorite_rounded : null,
          busy: widget.busy,
          onPressed: phone ? widget.onAllow : widget.onSkip,
        ),
        if (phone)
          Center(
            child: TextButton(
              onPressed: widget.busy ? null : widget.onSkip,
              child: Text(
                'Not now',
                style: t.body(14, FontWeight.w500).copyWith(color: c.text2),
              ),
            ),
          ),
        const SizedBox(height: Space.s2),
      ],
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final t = context.type;
    final c = context.colors;
    return GlassCard(
      radius: Radii.row,
      padding: const EdgeInsets.all(12),
      blur: false,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: c.text),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.body(15, FontWeight.w600)),
                Text(detail, style: t.body(13).copyWith(color: c.text2)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
