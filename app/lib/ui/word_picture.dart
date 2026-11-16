/// A newcomer word's picture (2026-11-17): a real photo for things you can point at, an
/// illustrated icon for actions, feelings and ideas, nothing where no picture fits.
library;

import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../app_services.dart';
import '../data/content_db.dart';
import '../platform/word_photos.dart';

/// Set at start-up (main.dart); null in tests, where photos are not downloaded.
WordPhotos? wordPhotos;

class WordPicture extends StatelessWidget {
  const WordPicture({
    super.key,
    required this.services,
    required this.cardId,
    this.size = 56,
    this.showCredit = false,
  });
  final AppServices services;
  final String cardId;
  final double size;

  /// Photo credit under the picture (licence attribution): on the big drill card.
  final bool showCredit;

  @override
  Widget build(BuildContext context) {
    final pic = services.content.wordPictures()[cardId];
    if (pic == null) return SizedBox.square(dimension: size);
    if (pic.kind == 'icon') {
      return Image.asset(
        'assets/icons/${pic.ref}.png',
        key: ValueKey('word-icon-$cardId'),
        width: size,
        height: size,
        errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
      );
    }
    return _Photo(pic: pic, size: size, showCredit: showCredit, cardId: cardId);
  }
}

class _Photo extends StatelessWidget {
  const _Photo({
    required this.pic,
    required this.size,
    required this.showCredit,
    required this.cardId,
  });
  final WordPictureRow pic;
  final double size;
  final bool showCredit;
  final String cardId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photos = wordPhotos;
    final box = BoxDecoration(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(size / 6),
    );
    if (photos == null) {
      return Container(width: size * 1.33, height: size, decoration: box);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FutureBuilder<File?>(
          future: photos.get(pic.ref),
          builder: (context, snap) {
            final f = snap.data;
            return ClipRRect(
              borderRadius: BorderRadius.circular(size / 6),
              child: f == null
                  ? Container(width: size * 1.33, height: size, decoration: box)
                  : Image.file(
                      f,
                      key: ValueKey('word-photo-$cardId'),
                      width: size * 1.33,
                      height: size,
                      fit: BoxFit.cover,
                      cacheWidth: (size * 1.33 * 3).round(),
                      errorBuilder: (_, _, _) => Container(
                        width: size * 1.33,
                        height: size,
                        decoration: box,
                      ),
                    ),
            );
          },
        ),
        if (showCredit && pic.credit.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              pic.credit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}
