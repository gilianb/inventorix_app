# inventorix_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

hhow to build and deploy(web):
flutter build web --release --dart-define=SUPABASE_URL=https://zfxuqieskmaseqshdfex.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpmeHVxaWVza21hc2Vxc2hkZmV4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk5MDAwMzIsImV4cCI6MjA3NTQ3NjAzMn0.aOui_AiG7iMFuHbkaQgODxqE0dw4q8Pgd3QBMKScenU --pwa-strategy=none --web-renderer canvaskit
cd build/web
vercel --prod

