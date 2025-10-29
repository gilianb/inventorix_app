// ignore_for_file: deprecated_member_use
/*Rôle : affiche la vignette du produit avec 
un ratio carte (0.72 par défaut configurable).*/

import 'package:flutter/material.dart';

const kAccentA = Color(0xFF6C5CE7);
const kAccentB = Color(0xFF00D1B2);

class MediaThumb extends StatelessWidget {
  const MediaThumb({
    super.key,
    required this.imageUrl,
    this.onOpen,
    this.aspectRatio = 3 / 2,
    this.isAsset = false,
  });

  final String imageUrl;
  final VoidCallback? onOpen;
  final double aspectRatio;
  final bool isAsset;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 1.2,
      shadowColor: kAccentA.withOpacity(.16),
      color: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (isAsset)
                  Image.asset(imageUrl, fit: BoxFit.cover)
                else
                  Image.network(imageUrl, fit: BoxFit.cover),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [kAccentA.withOpacity(.20), Colors.transparent],
                    ),
                  ),
                ),
                if (onOpen != null)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: kAccentB.withOpacity(.85),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.open_in_new,
                              size: 16, color: Colors.white),
                          SizedBox(width: 6),
                          Text('Ouvrir',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
