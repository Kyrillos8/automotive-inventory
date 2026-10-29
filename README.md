# مخزن قطع غيار الموتور — Automotive Engine Parts Inventory

Arabic-first, offline-only Flutter app (Drift/SQLite, Riverpod, GoRouter) for a piston-ring /
piston / engine-parts wholesaler: catalog with label specs, tags, vehicle compatibility,
unified Arabic/English search, inventory ledger, stocktaking, purchasing, wholesale/retail
sales, payments, returns, reports (CSV), backup/restore and PIN lock.

## Option A — get the APK from GitHub (no Flutter install needed)

1. Create an empty repository on github.com.
2. Copy `docs/github-actions-build-apk.yml` to `.github/workflows/build-apk.yml`.
3. Push this folder to the repository.
4. Open the repo → **Actions** → "Build APK" → when it finishes, download the
   `automotive-inventory-apk` artifact → install `app-release.apk` on the phone
   (allow "install unknown apps").

## Option B — build on your PC

```bash
flutter create --platforms=android --org com.kerolos --project-name automotive_inventory .
del test\widget_test.dart          # default counter test created by flutter create
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter build apk --release        # -> build/app/outputs/flutter-apk/app-release.apk
```

`test/database_test.dart` needs native SQLite on the PC (Windows: put `sqlite3.dll` on PATH).

## Notes
- The release APK is signed with the debug key (fine for installing on your own phone; set up
  a real keystore before publishing to the Play Store).
- See `docs/PLAN.md` for business rules, assumptions and known limitations.
