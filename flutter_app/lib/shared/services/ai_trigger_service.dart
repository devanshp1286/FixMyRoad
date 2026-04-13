import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../../core/constants.dart';

class AiTriggerService {
  /// Calls the FastAPI AI worker directly from Flutter.
  static Future<bool> triggerAnalysis({
    required String reportId,
    required String imageUrl,
  }) async {
    try {
      debugPrint('[AI Worker] Calling: ${AppConstants.aiWorkerUrl}/analyze');
      debugPrint('[AI Worker] Report ID: $reportId');
      debugPrint('[AI Worker] Image URL: $imageUrl');

      final url = Uri.parse('${AppConstants.aiWorkerUrl}/analyze');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'report_id': reportId,
          'image_url': imageUrl,
        }),
      ).timeout(const Duration(minutes: 5));

      debugPrint('[AI Worker] Response status: ${response.statusCode}');
      debugPrint('[AI Worker] Response body: ${response.body}');

      if (response.statusCode == 200) {
        debugPrint('[AI Worker] SUCCESS');
        return true;
      } else {
        debugPrint('[AI Worker] FAILED: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[AI Worker] ERROR: $e');
      debugPrint('[AI Worker] Make sure server is running at: ${AppConstants.aiWorkerUrl}');
      return false;
    }
  }
}