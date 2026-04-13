import 'dart:io';
import 'dart:math';
import 'package:image/image.dart' as img;

import '../../core/constants.dart';

class PhotoQualityResult {
  final bool isAccepted;
  final String? rejectionReason;
  final double blurScore;
  final double brightnessScore;

  const PhotoQualityResult({
    required this.isAccepted,
    this.rejectionReason,
    required this.blurScore,
    required this.brightnessScore,
  });
}

class PhotoQualityChecker {
  /// Checks image quality before upload.
  /// Returns a [PhotoQualityResult] with pass/fail and scores.
  static Future<PhotoQualityResult> check(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      return const PhotoQualityResult(
        isAccepted: false,
        rejectionReason: 'Could not read image.',
        blurScore: 0,
        brightnessScore: 0,
      );
    }

    // Convert to greyscale for Laplacian
    final grey = img.grayscale(image);

    // Compute Laplacian variance (blur detection)
    final blurScore = _laplacianVariance(grey);

    // Compute mean brightness
    final brightness = _meanBrightness(grey);

    if (blurScore < AppConstants.blurThreshold) {
      return PhotoQualityResult(
        isAccepted: false,
        rejectionReason:
            'Photo is too blurry. Please retake with a steady hand.',
        blurScore: blurScore,
        brightnessScore: brightness,
      );
    }

    if (brightness < AppConstants.brightnessThreshold) {
      return PhotoQualityResult(
        isAccepted: false,
        rejectionReason:
            'Photo is too dark. Please take the photo in better lighting.',
        blurScore: blurScore,
        brightnessScore: brightness,
      );
    }

    return PhotoQualityResult(
      isAccepted: true,
      blurScore: blurScore,
      brightnessScore: brightness,
    );
  }

  // Laplacian variance — higher = sharper image
  static double _laplacianVariance(img.Image grey) {
    final w = grey.width;
    final h = grey.height;
    final values = <double>[];

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final center = _lum(grey.getPixel(x, y));
        final top    = _lum(grey.getPixel(x, y - 1));
        final bottom = _lum(grey.getPixel(x, y + 1));
        final left   = _lum(grey.getPixel(x - 1, y));
        final right  = _lum(grey.getPixel(x + 1, y));
        final lap = (4 * center) - top - bottom - left - right;
        values.add(lap * lap);
      }
    }

    if (values.isEmpty) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance = values
            .map((v) => pow(v - mean, 2))
            .reduce((a, b) => a + b) /
        values.length;
    return sqrt(variance);
  }

  // Mean luminance 0–255
  static double _meanBrightness(img.Image grey) {
    double sum = 0;
    final total = grey.width * grey.height;
    for (int y = 0; y < grey.height; y++) {
      for (int x = 0; x < grey.width; x++) {
        sum += _lum(grey.getPixel(x, y));
      }
    }
    return sum / total;
  }

  static double _lum(img.Pixel p) => p.luminance.toDouble();
}
