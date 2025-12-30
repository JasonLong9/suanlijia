import 'dart:io';
import 'package:flutter/foundation.dart';
import '../dev_settings.dart/develop_settings.dart';

// ignore: non_constant_identifier_names
void VLOG0(Object? s) {
  final msg = '[${DateTime.now().toIso8601String()}] $s';
  
  // 1. Print to console (always in debug mode)
  if (DevelopSettings.isDebugging || kDebugMode) {
    // ignore: avoid_print
    print(msg);
  }

  // 2. ALWAYS write to file on Windows (critical for debugging)
  if (!kIsWeb && Platform.isWindows) {
    try {
      final logDir = Directory(r'C:\ProgramData\SLC\logs');
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }
      final logFile = File('${logDir.path}\\agent.log');
      logFile.writeAsStringSync('$msg\n', mode: FileMode.append, flush: true);
    } catch (e) {
      // Ignore file write errors to avoid crashing
      // ignore: avoid_print
      print('[VLOG0 ERROR] Failed to write log: $e');
    }
  }
}
