import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Loads bundled artwork notices only when Flutter's license page is opened.
/// Registration itself performs no asset reads or network requests.
void registerBundledAssetLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final notice = await rootBundle.loadString('assets/reactions/LICENSE');
    final license = await rootBundle.loadString(
      'assets/reactions/LICENSE-APACHE-2.0',
    );
    yield LicenseEntryWithLineBreaks(['Noto Emoji'], '$notice\n$license');
  });
}
