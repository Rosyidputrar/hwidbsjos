import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../agent/agent_controller.dart';
import 'settings_screen.dart';
import 'kit.dart';
import 'i18n.dart';
import 'theme.dart';

/// First-run welcome: what the agent is, then straight to connecting a
/// provider — an account, an API key, or the user's own endpoint.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.agent});
  final AgentController agent;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final pages = PageController();
  int page = 0;

  // Carousel: slide 1 is the brand, slide 2 the bring-your-own models,
  // slide 3 ends on the connect action.
  static const _slides = [
    (_Hero.logo, 'Rynex AI Agent', 'An AI coding agent on your phone.'),
    (
      _Hero.models,
      'Every model,\nyour choice',
      'Claude, GPT, Gemini, DeepSeek and more — bring your own account, API key or endpoint.'
    ),
    (
      _Hero.key,
      'Connect a provider\nto start',
      'Sign in, paste an API key, or point Rynex at your own server. Nothing else to configure.'
    ),
  ];

  // Home takes over from here and offers to connect a model if none is set.
  void _start() => Appearance.instance.finishOnboarding();

  void _next() => Motion.reduced(context)
      ? pages.jumpToPage((pages.page ?? 0).round() + 1)
      : pages.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);

  /// Push the providers screen; coming back with a provider connected
  /// finishes onboarding straight into Home. Backing out without connecting
  /// leaves the user on this slide, with Skip still available.
  Future<void> _addKey() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(agent: widget.agent)),
    );
    if (!mounted) return;
    await widget.agent.refreshProviders();
    if (mounted && widget.agent.providers.any((p) => p.configured)) _start();
  }

  @override
  void dispose() {
    pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = Theme.of(context).textTheme;
    final last = page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  // A 48 dp touch box around the small pill it draws.
                  Semantics(
                    button: true,
                    label: tr('Skip'),
                    child: TapTarget(
                      onTap: _start,
                      child: ExcludeSemantics(
                        child: Material(
                          color: p.surface,
                          borderRadius: BorderRadius.circular(Radii.md),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(Radii.md),
                            onTap: _start,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              child: Text(
                                tr('Skip'),
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pages,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => page = i),
                itemBuilder: (context, i) {
                  final (hero, title, body) = _slides[i];
                  // Scrolls when the page is taller than the room (a phone on its side, very large text), and the picture
                  // shrinks to leave room for the words.
                  return LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: (box.maxHeight * 0.45).clamp(96.0, 240.0),
                              child: Center(child: _heroWidget(hero)),
                            ),
                            SizedBox(height: box.maxHeight < 400 ? 16 : 40),
                            Text(tr(title), textAlign: TextAlign.center, style: text.displayMedium),
                            const SizedBox(height: 14),
                            Text(
                              tr(body),
                              textAlign: TextAlign.center,
                              style: text.bodyLarge?.copyWith(color: p.muted),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // The dots are one thing to a screen reader: which page this is.
            Semantics(
              label: tr('Page {n} of {total}')
                  .replaceAll('{n}', '${page + 1}')
                  .replaceAll('{total}', '${_slides.length}'),
              child: ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < _slides.length; i++)
                      AnimatedContainer(
                        duration: Motion.of(context, const Duration(milliseconds: 220)),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          // The app accent, like every other selected state (accentAlt is for categories).
                          color: i == page ? p.accent : Colors.transparent,
                          border: Border.all(color: i == page ? p.accent : p.faint, width: 1.5),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: PrimaryButton(label: last ? tr('Connect a provider') : tr('Next'), onPressed: last ? _addKey : _next),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroWidget(_Hero hero) => switch (hero) {
    _Hero.logo => Image.asset('assets/brand/logo.png', height: 200),
    _Hero.models => const IconTile(icon: LucideIcons.sparkles, size: 132),
    _Hero.key => const IconTile(icon: LucideIcons.keyRound, size: 132),
  };
}

enum _Hero { logo, models, key }
