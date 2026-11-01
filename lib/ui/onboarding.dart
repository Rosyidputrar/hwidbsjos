import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../agent/agent_controller.dart';
import 'i18n.dart';
import 'kit.dart';
import 'illustration.dart';
import 'theme.dart';

/// First-run welcome: what Rynex is, then straight to connecting a model.
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
              padding: const EdgeInsets.fromLTRB(Space.page, Space.md, Space.md, 0),
              child: Row(
                children: [
                  const LogoMark(size: 28),
                  const SizedBox(width: Space.sm),
                  Text('Rynex', style: text.titleMedium),
                  const Spacer(),
                  if (!last)
                    TextButton(
                      onPressed: _start,
                      style: TextButton.styleFrom(foregroundColor: p.muted),
                      child: Text(tr('Skip')),
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
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.page),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Hero(illustration: art),
                        const SizedBox(height: Space.xxl),
                        IconTile(icon: icon, size: 36),
                        const SizedBox(height: Space.lg),
                        Text(tr(title), style: text.displayMedium),
                        const SizedBox(height: Space.md),
                        Text(tr(body), style: text.bodyLarge?.copyWith(color: p.muted)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.page, Space.lg, Space.page, Space.md),
              child: Row(
                children: [
                  // Progress: one bar per slide, the current one stretched.
                  for (var i = 0; i < _slides.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.only(right: 6),
                      width: i == page ? 28 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i <= page ? p.accent : p.border,
                        borderRadius: BorderRadius.circular(Radii.pill),
                      ),
                    ),
                  const Spacer(),
                  SizedBox(
                    width: 170,
                    child: PrimaryButton(
                      label: last ? tr('Get started') : tr('Next'),
                      icon: last ? LucideIcons.arrowRight : null,
                      onPressed: last
                          ? _start
                          : () =>
                                pages.nextPage(duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: StorysetCredit(openUrl: widget.agent.client.openUrl),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.illustration});
  final String illustration;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      height: 280,
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
      padding: const EdgeInsets.all(Space.lg),
      child: Illustration(illustration, height: 248),
    );
  }
}
