import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../agent/agent_controller.dart';
import 'settings_screen.dart';
import 'kit.dart';
import 'i18n.dart';
import 'illustration.dart';
import 'theme.dart';

/// First-run welcome: what Rynex is, then straight to connecting a
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

  static const _slides = [
    ('ai', LucideIcons.sparkles, 'Boost your\nproductivity', 'Chat with a coding agent that runs right on your phone.'),
    (
      'linux',
      LucideIcons.squareTerminal,
      'Real Linux,\nin your pocket',
      'Install Python, Node and more with apt. No root needed.',
    ),
    (
      'search',
      LucideIcons.globe,
      'Search, build\nand preview',
      'pi looks things up on the web and shows your pages live.',
    ),
    ('launch', LucideIcons.rocket, 'Ship it\nanywhere', 'Deploy to Vercel, GitHub Pages or your own server.'),
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
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
              child: Row(
                children: [
                  const LogoMark(size: 28),
                  const SizedBox(width: 8),
                  Text(tr('Rynex'), style: text.titleMedium),
                  const Spacer(),
                  if (!last)
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
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: pages,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => page = i),
                itemBuilder: (context, i) {
                  final (art, icon, title, body) = _slides[i];
                  // Scrolls when the page is taller than the room (a phone on its side, very large text), and the picture
                  // shrinks to leave room for the words.
                  return LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Hero(illustration: art, height: (box.maxHeight * 0.42).clamp(120.0, 280.0)),
                            const SizedBox(height: 28),
                            IconTile(icon: icon, size: 36),
                            const SizedBox(height: 16),
                            Text(tr(title), style: text.displayMedium),
                            const SizedBox(height: 12),
                            Text(tr(body), style: text.bodyLarge?.copyWith(color: p.muted)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: [
                  // Progress: one bar per slide, the current one stretched. The bars are one thing to a screen
                  // reader: which page this is.
                  Semantics(
                    label: tr('Page {n} of {total}')
                        .replaceAll('{n}', '${page + 1}')
                        .replaceAll('{total}', '${_slides.length}'),
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < _slides.length; i++)
                            AnimatedContainer(
                              duration: Motion.of(context, const Duration(milliseconds: 260)),
                              curve: Curves.easeOutCubic,
                              margin: const EdgeInsets.only(right: 6),
                              width: i == page ? 28 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: i <= page ? p.accent : p.border,
                                borderRadius: BorderRadius.circular(Radii.pill),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 170,
                    child: PrimaryButton(
                      label: last ? tr('Add an endpoint') : tr('Next'),
                      icon: last ? LucideIcons.arrowRight : null,
                      onPressed: last ? _addKey : _next,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: StorysetCredit(openUrl: widget.agent.client.openUrl),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.illustration, required this.height});
  final String illustration;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: p.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [p.accent.withValues(alpha: 0.16), p.surface],
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Illustration(illustration, height: height - 32),
    );
  }
}
