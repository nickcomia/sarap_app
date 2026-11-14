import 'package:flutter/material.dart';
import '../../theme.dart';

/// Text field for an image link (for example a raw.githubusercontent.com
/// URL) with a live preview underneath. Leave it empty for "no image".
class ImageUrlField extends StatelessWidget {
  const ImageUrlField({super.key, required this.controller});

  final TextEditingController controller;

  static bool isValidUrl(String s) =>
      s.startsWith('http://') || s.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final url = value.text.trim();
        final valid = isValidUrl(url);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (valid) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  url,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  // The preview is small, so decode it small.
                  cacheWidth: 800,
                  errorBuilder: (_, __, ___) => Container(
                    height: 160,
                    width: double.infinity,
                    color: AppColors.chipBg,
                    alignment: Alignment.center,
                    child: const Text('Could not load this image link',
                        style: TextStyle(color: AppColors.muted)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: controller,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Image URL (optional)',
                hintText: 'https://raw.githubusercontent.com/...',
                helperText:
                    'Paste a link to the photo. Tip: resize it to about 800 px wide '
                    'before uploading it. Leave empty for no photo.',
                prefixIcon: Icon(Icons.image_outlined),
              ),
              validator: (v) {
                final s = v?.trim() ?? '';
                if (s.isEmpty) return null;
                return isValidUrl(s) ? null : 'The link must start with https://';
              },
            ),
          ],
        );
      },
    );
  }
}