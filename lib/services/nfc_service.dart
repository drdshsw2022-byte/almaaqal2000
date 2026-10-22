import 'dart:async';
import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// نتيجة قراءة NFC: إما رمز هوية من هاتف طالب، أو معرّف شريحة بطاقة.
class NfcRead {
  final String? payload; // من هاتف الطالب (HCE)
  final String? uid; // معرّف الشريحة (HEX)
  /// هاتف يعمل بالـ NFC لكنه لا يقدّم هوية المعقل (التطبيق غير مثبت أو لم يُسجَّل الدخول فيه)
  final bool phoneWithoutId;
  /// تفاصيل فنية لشاشة اختبار NFC
  final String info;
  NfcRead({this.payload, this.uid, this.phoneWithoutId = false, this.info = ''});
}

class NfcService {
  NfcService._();

  static const _hceKey = 'hce_payload';

  static Future<bool> isAvailable() async {
    try {
      return await NfcManager.instance.isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// على هاتف الطالب: يحفظ رمز الهوية ليقدّمه الهاتف عند تقريبه من قارئ الدكتور.
  /// تقرؤه خدمة Android الأصلية (StudentHceService) من SharedPreferences.
  static Future<void> setStudentPayload(String? payload) async {
    final p = await SharedPreferences.getInstance();
    if (payload == null) {
      await p.remove(_hceKey);
    } else {
      await p.setString(_hceKey, payload);
    }
  }

  static Uint8List _hex(String h) => Uint8List.fromList([
        for (var i = 0; i < h.length; i += 2)
          int.parse(h.substring(i, i + 2), radix: 16)
      ]);

  static String _toHex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

  static String? _identifier(NfcTag tag) {
    final id = NfcA.from(tag)?.identifier ??
        IsoDep.from(tag)?.identifier ??
        MifareClassic.from(tag)?.identifier ??
        MifareUltralight.from(tag)?.identifier ??
        NfcB.from(tag)?.identifier ??
        NfcF.from(tag)?.identifier ??
        NfcV.from(tag)?.identifier;
    if (id == null || id.isEmpty) return null;
    return _toHex(id);
  }

  static List<String> _techs(NfcTag tag) =>
      tag.data.keys.map((k) => '$k').toList();

  /// يقرأ وسيطاً واحداً (هاتف طالب أو بطاقة) ويحدد نوعه.
  static Future<NfcRead> _readTag(NfcTag tag) async {
    final techs = _techs(tag);
    final uid = _identifier(tag);
    final log = StringBuffer('التقنيات: ${techs.join(', ')}\nUID: ${uid ?? '-'}');
    final iso = IsoDep.from(tag);
    if (iso != null) {
      final aid = _hex(AppConfig.nfcAid);
      final apdu = Uint8List.fromList(
          [0x00, 0xA4, 0x04, 0x00, aid.length, ...aid, 0x00]);
      for (var attempt = 1; attempt <= 3; attempt++) {
        try {
          final res = await iso.transceive(data: apdu);
          log.write('\nSELECT($attempt): ${_toHex(res)}');
          final n = res.length;
          if (n >= 2 && res[n - 2] == 0x90 && res[n - 1] == 0x00) {
            final text = String.fromCharCodes(res.sublist(0, n - 2)).trim();
            if (text.isNotEmpty) {
              return NfcRead(payload: text, uid: uid, info: '$log');
            }
          }
          // رد صريح بأن الهوية غير موجودة: هاتف عليه التطبيق بلا تسجيل دخول
          if (n == 2 && res[0] == 0x6A && res[1] == 0x82) {
            return NfcRead(uid: uid, phoneWithoutId: true, info: '$log');
          }
          break;
        } catch (e) {
          log.write('\nSELECT($attempt) خطأ: $e');
          if (attempt < 3) {
            await Future.delayed(const Duration(milliseconds: 120));
          }
        }
      }
      // هاتف (HCE) يعطي معرّفاً عشوائياً يبدأ بـ 08، ولا يصلح كبطاقة
      if (uid != null && uid.length == 8 && uid.startsWith('08')) {
        return NfcRead(uid: uid, phoneWithoutId: true, info: '$log');
      }
    }
    return NfcRead(uid: uid, info: '$log');
  }

  /// يبدأ القراءة المستمرة على هاتف الدكتور. كل بطاقة/هاتف يُقرَّب يُستدعى له [onRead].
  static Future<void> startReading(
      void Function(NfcRead r) onRead, void Function(String e) onError) async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    try {
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            final r = await _readTag(tag);
            if (r.payload == null && r.uid == null && !r.phoneWithoutId) {
              onError('تعذّرت قراءة البطاقة، أعد تقريبها وثبّتها ثانيتين');
            } else {
              onRead(r);
            }
          } catch (e) {
            onError('خطأ في قراءة NFC: $e');
          }
        },
        onError: (e) async => onError('خطأ NFC: ${e.message}'),
      );
    } catch (e) {
      onError('تعذّر تشغيل قارئ NFC: $e');
    }
  }

  /// قراءة وسيط واحد مع التفاصيل (لشاشة الاختبار).
  static Future<NfcRead?> readOnce(
      {Duration timeout = const Duration(seconds: 40)}) async {
    final c = Completer<NfcRead?>();
    _pendingRead = c;
    await startReading((r) {
      if (!c.isCompleted) c.complete(r);
    }, (e) {
      if (!c.isCompleted) c.complete(NfcRead(info: e));
    });
    final r = await c.future.timeout(timeout, onTimeout: () => null);
    _pendingRead = null;
    await stopReading();
    return r;
  }

  static Completer<NfcRead?>? _pendingRead;

  static Future<void> stopReading() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }

  /// قراءة بطاقة واحدة (لربطها بطالب). تعيد معرّف الشريحة أو null عند الإلغاء.
  static Completer<String?>? _pending;

  static Future<String?> readOneUid(
      {Duration timeout = const Duration(seconds: 30)}) async {
    final c = Completer<String?>();
    _pending = c;
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    await NfcManager.instance.startSession(onDiscovered: (tag) async {
      final uid = _identifier(tag);
      if (!c.isCompleted) c.complete(uid);
    });
    final r = await c.future.timeout(timeout, onTimeout: () => null);
    _pending = null;
    await stopReading();
    return r;
  }

  /// إلغاء انتظار [readOneUid].
  static void cancelOne() {
    final c = _pending;
    if (c != null && !c.isCompleted) c.complete(null);
    final d = _pendingRead;
    if (d != null && !d.isCompleted) d.complete(null);
  }
}
