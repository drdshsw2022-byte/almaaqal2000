#!/usr/bin/env bash
# يولّد ملفات منصة Android (إن لم تكن موجودة) ويضبط إعداداتها للتطبيق.
set -euo pipefail

PKG_DIR=iq/edu/almaqal/almaqal_attendance

if [ ! -f android/app/build.gradle ] && [ ! -f android/app/build.gradle.kts ]; then
  flutter create --platforms=android --org iq.edu.almaqal \
    --project-name almaqal_attendance --no-pub .
fi

# ملف الاختبار الافتراضي يشير إلى MyApp غير الموجود
rm -f test/widget_test.dart

APP_GRADLE=android/app/build.gradle
SETTINGS=android/settings.gradle
MANIFEST=android/app/src/main/AndroidManifest.xml

if [ -f "$APP_GRADLE" ]; then
  # Firebase Auth يتطلب Android 6.0 فأعلى
  sed -i -E 's/minSdk(Version)?( *= *| +)flutter\.minSdkVersion/minSdk = 23/' "$APP_GRADLE"
fi

if [ -f "$SETTINGS" ]; then
  # مكتبات Firebase الحديثة تحتاج Kotlin 1.9 فأعلى
  sed -i -E 's/(id "org\.jetbrains\.kotlin\.android" version ")[^"]*(")/\11.9.24\2/' "$SETTINGS"
fi

# خدمة NFC (HCE): هاتف الطالب يقدّم هويته لهاتف الدكتور
mkdir -p "android/app/src/main/kotlin/$PKG_DIR" android/app/src/main/res/xml android/app/src/main/res/values
cp ci/android/StudentHceService.kt "android/app/src/main/kotlin/$PKG_DIR/StudentHceService.kt"
cp ci/android/apduservice.xml android/app/src/main/res/xml/apduservice.xml
cp ci/android/hce_strings.xml android/app/src/main/res/values/hce_strings.xml

python3 - "$MANIFEST" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p, encoding='utf-8').read()
s = re.sub(r'android:label="[^"]*"', 'android:label="جامعة المعقل"', s, count=1)
perms = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.CAMERA"/>',
    '<uses-permission android:name="android.permission.NFC"/>',
    '<uses-feature android:name="android.hardware.nfc" android:required="false"/>',
    '<uses-feature android:name="android.hardware.nfc.hce" android:required="false"/>',
    '<uses-feature android:name="android.hardware.camera" android:required="false"/>',
]
head = re.search(r'<manifest[^>]*>', s)
add = ''.join('\n    ' + x for x in perms if x.split('"')[1] not in s)
s = s[:head.end()] + add + s[head.end():]
service = '''
        <service
            android:name=".StudentHceService"
            android:exported="true"
            android:permission="android.permission.BIND_NFC_SERVICE">
            <intent-filter>
                <action android:name="android.nfc.cardemulation.action.HOST_APDU_SERVICE"/>
            </intent-filter>
            <meta-data
                android:name="android.nfc.cardemulation.host_apdu_service"
                android:resource="@xml/apduservice"/>
        </service>
    '''
# فتح الروابط (الدروس) عبر url_launcher على Android 11+
https_intent = '''
        <intent>
            <action android:name="android.intent.action.VIEW"/>
            <data android:scheme="https"/>
        </intent>'''
if 'android:scheme="https"' not in s:
    if '<queries>' in s:
        s = s.replace('<queries>', '<queries>' + https_intent, 1)
    else:
        s = s.replace('</manifest>', '    <queries>' + https_intent + '\n    </queries>\n</manifest>')
if 'StudentHceService' not in s:
    i = s.rindex('</application>')
    s = s[:i] + service + s[i:]
open(p, 'w', encoding='utf-8').write(s)
PY

echo "----- settings.gradle -----"; cat "$SETTINGS" || true
echo "----- app/build.gradle -----"; cat "$APP_GRADLE" || true
echo "----- AndroidManifest.xml -----"; cat "$MANIFEST"
