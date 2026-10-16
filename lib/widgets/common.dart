import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme.dart';
import '../models.dart';

/// Renders a photo from either a bundled local asset path
/// (e.g. "assets/photos/adobo.jpg") or a network URL, auto-detected,
/// with a graceful fallback if the image is missing or fails to load.
/// Network photos are cached on disk after the first download.
class SmartImage extends StatelessWidget {
  final String? source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget fallback;

  const SmartImage({
    super.key,
    required this.source,
    required this.fallback,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (source == null || source!.isEmpty) return fallback;

    final isNetwork = source!.startsWith('http://') || source!.startsWith('https://');
    if (isNetwork) {
      return CachedNetworkImage(
        imageUrl: source!,
        width: width,
        height: height,
        fit: fit,
        memCacheWidth: width == null ? null : (width! * 3).round(),
        fadeInDuration: const Duration(milliseconds: 150),
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      );
    }
    return Image.asset(
      source!,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

/// A rounded, tappable chip used across onboarding for multi-select
/// preferences, readable in both light and dark themes.
class SarapChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const SarapChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          gradient: selected ? AppGradients.primary : null,
          color: selected ? null : colors.chipBg,
          borderRadius: BorderRadius.circular(30),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : colors.navy,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}

/// Small progress header used on every onboarding step ("Step X of 4").
class StepProgress extends StatelessWidget {
  final int step; // 1-based
  final int totalSteps;
  final String title;
  final String subtitle;
  const StepProgress({
    super.key,
    required this.step,
    required this.totalSteps,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(totalSteps, (i) {
            final active = i < step;
            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i == totalSteps - 1 ? 0 : 6),
                height: 6,
                decoration: BoxDecoration(
                  gradient: active ? AppGradients.primary : null,
                  color: active ? null : colors.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 6),
        Text('Step $step of $totalSteps',
            style: TextStyle(
                color: colors.muted,
                fontSize: 12.5,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 22),
      ],
    );
  }
}

/// Percentage badge shown on restaurant match cards. A solid gradient
/// pill, so it looks the same on light and dark cards.
class MatchBadge extends StatelessWidget {
  final int percent;
  const MatchBadge({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        gradient: AppGradients.secondary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        '$percent% match',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

/// The restaurant "match card". Elevated in light mode, bordered in dark
/// mode (shadows barely show on dark), with the photo dimmed slightly in
/// dark mode so white-background logos don't glare.
class RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  final VoidCallback onTap;
  final VoidCallback onSaveTap;
  const RestaurantCard({
    super.key,
    required this.restaurant,
    required this.onTap,
    required this.onSaveTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(22),
          boxShadow: isDark ? null : AppShadows.card,
          border: isDark ? Border.all(color: colors.border, width: 1) : null,
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 84,
                height: 84,
                foregroundDecoration: isDark
                    ? BoxDecoration(color: Colors.black.withValues(alpha: 0.25))
                    : null,
                child: SmartImage(
                  source: restaurant.imageUrl,
                  width: 84,
                  height: 84,
                  fallback: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(restaurant.accentColorValue),
                          Color(restaurant.accentColorValue).withValues(alpha: 0.6),
                        ],
                      ),
                    ),
                    child: const Icon(Icons.restaurant, color: Colors.white, size: 30),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(restaurant.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      InkWell(
                        onTap: onSaveTap,
                        borderRadius: BorderRadius.circular(20),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            restaurant.isSaved
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: restaurant.isSaved ? colors.primary : colors.muted,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${restaurant.type} • ${restaurant.cuisine}',
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      MatchBadge(percent: restaurant.matchPercent),
                      const SizedBox(width: 8),
                      Icon(Icons.star_rounded, size: 16, color: Colors.amber.shade600),
                      const SizedBox(width: 2),
                      Text('${restaurant.rating}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.navy)),
                      const SizedBox(width: 8),
                      Text('${restaurant.distanceKm} km',
                          style: Theme.of(context).textTheme.bodyMedium),
                      const Spacer(),
                      Text(restaurant.priceRange,
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: colors.navy)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labelled statistic used on the Profile screen's Health Stats card.
class StatPill extends StatelessWidget {
  final String label;
  final String value;
  const StatPill({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: colors.chipBg,
              borderRadius: BorderRadius.circular(14),
              boxShadow: isDark ? null : AppShadows.soft,
              border: isDark ? Border.all(color: colors.border, width: 1) : null,
            ),
            alignment: Alignment.center,
            child: Text(value,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, color: colors.navy)),
          ),
          const SizedBox(height: 6),
          Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: colors.muted)),
        ],
      ),
    );
  }
}

/// Labeled account-menu row used on the Profile screen.
class ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;
  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = danger ? colors.danger : colors.navy;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: colors.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark ? null : AppShadows.soft,
          border: isDark ? Border.all(color: colors.border, width: 1) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: danger
                    ? colors.danger.withValues(alpha: 0.1)
                    : colors.chipSelectedBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 19, color: danger ? color : colors.primaryDark),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600, color: color)),
            ),
            if (!danger)
              Icon(Icons.chevron_right_rounded, color: colors.muted, size: 22),
          ],
        ),
      ),
    );
  }
}