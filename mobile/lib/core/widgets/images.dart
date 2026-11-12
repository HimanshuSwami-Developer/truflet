import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Network image (Cloudinary / Django media) with the app's placeholder colour.
class Img extends StatelessWidget {
  final String? url;
  final double? width, height;
  final BorderRadius? radius;
  final String fallback;
  const Img(this.url, {super.key, this.width, this.height, this.radius, this.fallback = 'turf'});

  @override
  Widget build(BuildContext context) {
    final Widget child = (url == null || url!.isEmpty)
        ? Image.asset('assets/images/$fallback.jpg', width: width, height: height, fit: BoxFit.cover)
        : CachedNetworkImage(
            imageUrl: url!,
            width: width,
            height: height,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, _) => Container(color: const Color(0xFFE8F0E4)),
            errorWidget: (_, _, _) => Image.asset('assets/images/$fallback.jpg', fit: BoxFit.cover),
          );
    return radius == null ? child : ClipRRect(borderRadius: radius!, child: child);
  }
}
