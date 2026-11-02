import 'package:flutter/material.dart';
import '../theme.dart';

/// "About SARAP" screen, opened from Settings / Profile.
/// Answers: What is it? Why was it developed? What problem does it solve?
/// Who developed it? What are its goals?
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About SARAP')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            Text('SARAP', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Smart AI-Based Restaurant and Eatery Finder with Personalized '
              'Meal Planning for Tanauan City, Batangas',
              style: TextStyle(color: context.colors.muted, fontSize: 13.5),
            ),
            const SizedBox(height: 18),

            _AboutCard(
              icon: Icons.restaurant_menu,
              question: 'What is the application?',
              initiallyExpanded: true,
              children: const [
                _Para(
                  'SARAP is an Android mobile app that helps people in Tanauan '
                  'City, Batangas find nearby restaurants and eateries based on '
                  'their location, budget, cuisine, and dietary needs.',
                ),
                _Para(
                  'It also builds personalized daily and weekly meal plans with '
                  'calorie tracking, using the actual menus of local eateries, '
                  'from roadside carinderias and lomi houses to modern cafés.',
                ),
              ],
            ),

            _AboutCard(
              icon: Icons.lightbulb_outline,
              question: 'Why was it developed?',
              children: const [
                _Para(
                  'Tanauan City\'s food scene is growing fast, but there is no '
                  'central digital platform for it. Small, family-owned eateries '
                  'have limited online visibility, so many people default to '
                  'big fast-food chains.',
                ),
                _Para(
                  'At the same time, more residents are watching their health, '
                  'including those managing diabetes, high blood pressure, or '
                  'their weight, yet they rarely have nutritional information '
                  'when eating out. SARAP was built to connect local food with '
                  'personal wellness goals.',
                ),
              ],
            ),

            _AboutCard(
              icon: Icons.track_changes,
              question: 'What problem does it solve?',
              children: const [
                _Bullet('Finding places to eat that match your location, budget, and cravings.'),
                _Bullet('Local Tanaueño eateries being overlooked because they lack online visibility.'),
                _Bullet('Not knowing the calories or nutrition of meals when dining out.'),
                _Bullet('Following a healthy diet, since SARAP builds meal plans from real menus of nearby eateries.'),
              ],
            ),

            _AboutCard(
              icon: Icons.groups_outlined,
              question: 'Who developed the application?',
              children: const [
                _Para(
                  'SARAP was developed by Nick Aeron M. Comia and Kim Nicole M. '
                  'Pilapil, Bachelor of Science in Information Technology '
                  'students (Business Analytics specialization).',
                ),
                _Para(
                  'It is a capstone project of the College of Informatics and '
                  'Computing Sciences, Batangas State University, The National '
                  'Engineering University, JPLPC – Malvar Campus (May 2026).',
                ),
                _Para('Adviser: Noel L. Virrey, BSCS'),
              ],
            ),

            _AboutCard(
              icon: Icons.flag_outlined,
              question: 'What are its goals?',
              children: const [
                _Bullet('Make it easy to discover nearby restaurants with maps, distance, and routes.'),
                _Bullet('Give personalized restaurant and meal suggestions using AI.'),
                _Bullet('Create daily and weekly meal plans and track calorie intake.'),
                _Bullet('Improve the visibility of small and local food businesses.'),
                _Bullet('Encourage healthier eating through accessible nutritional information.'),
                _Bullet('Celebrate and support Tanauan City\'s local food heritage.'),
              ],
            ),

            const SizedBox(height: 8),
            Text(
              'SARAP does not provide medical advice, diagnosis, or treatment. '
              'Calorie and nutrition values are estimates and may vary by '
              'serving size and preparation.',
              style: TextStyle(color: context.colors.muted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  final IconData icon;
  final String question;
  final List<Widget> children;
  final bool initiallyExpanded;

  const _AboutCard({
    required this.icon,
    required this.question,
    required this.children,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.colors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: context.colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: initiallyExpanded,
            shape: const Border(),
            collapsedShape: const Border(),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            leading: Icon(icon, color: context.colors.primaryDark),
            title: Text(
              question,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
            children: children,
          ),
        ),
      ),
    );
  }
}

class _Para extends StatelessWidget {
  final String text;
  const _Para(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.5)),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 8),
            child: Icon(Icons.check_circle, size: 16, color: context.colors.primaryDark),
          ),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.45)),
          ),
        ],
      ),
    );
  }
}