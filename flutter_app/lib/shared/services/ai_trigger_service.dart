import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../../core/constants.dart';

class AiTriggerService {
  /// Check if AI worker is online
  static Future<bool> checkHealth() async {
    try {
      debugPrint('[AI Health] Checking AI worker at: ${AppConstants.aiWorkerUrl}/health');
      final response = await http.get(
        Uri.parse('${AppConstants.aiWorkerUrl}/health'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        debugPrint('[AI Health] ✓ AI worker is online');
        debugPrint('[AI Health] Response: ${response.body}');
        return true;
      } else {
        debugPrint('[AI Health] ✗ AI worker returned status ${response.statusCode}');
        return false;
      }
    } catch (e) {
      debugPrint('[AI Health] ✗ Cannot reach AI worker: $e');
      debugPrint('[AI Health] URL: ${AppConstants.aiWorkerUrl}');
      return false;
    }
  }

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