import 'dart:html' as html;

/// Browser Fullscreen API — hides OS/browser chrome (tabs, address bar).
void requestBrowserFullscreen() {
  html.document.documentElement?.requestFullscreen();
}

void exitBrowserFullscreen() {
  html.document.exitFullscreen();
}
