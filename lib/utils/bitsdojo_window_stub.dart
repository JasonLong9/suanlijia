import 'package:flutter/material.dart';

void doWhenWindowReady(VoidCallback callback) {
  // Do nothing on web
}

final appWindow = WebAppWindow();

class WebAppWindow {
  set minSize(Size size) {}
  set size(Size size) {}
  set alignment(Alignment alignment) {}
  void show() {}
  void hide() {}
  void close() {}
}
