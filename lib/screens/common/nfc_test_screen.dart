import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repo.dart';
import '../../services/nfc_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// اختبار NFC: يقرأ وسيطاً واحداً ويعرض ما اكتُشف، لتشخيص مشاكل القراءة.
class NfcTestScreen extends StatefulWidget {
  const NfcTestScreen({super.key});

  @override
  State<NfcTestScreen> createState() => _NfcTestScreenState();
}

class _NfcTestScreenState extends State<NfcTestScreen> {
  bool? _available;
  bool _waiting = false;
  NfcRead? _last;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    NfcService.cancelOne();
    NfcService.stopReading();
    super.dispose();
  }

  Future<void> _check() async {
    final a = await NfcService.isAvailable();
    if (mounted) setState(() => _available = a);
  }

  Future<void> _read() async {
    await _check();
    if (_available != true) return;
    setState(() {
      _waiting = true;
      _last = null;
      _timedOut = false;
    });
    final r = await NfcService.readOnce();
    if (!mounted) return;
    setState(() {
      _waiting = false;
      _last = r;
      _timedOut = r == null;
    });
  }

  String _verdict(NfcRead r) {
    if (r.payload != null) {
      final p = StudentCode.parse(r.payload!);
      return p.id != null
          ? 'هاتف طالب يعمل بشكل صحيح ✔\nالرقم المعرفي: ${p.id}'
          : 'هاتف أرسل بيانات غير معروفة: ${r.payload}';
    }
    if (r.phoneWithoutId) {
      return 'هاتف يدعم NFC لكنه لا يقدّم هوية.\nعلى هاتف الطالب: ثبّت آخر نسخة من التطبيق، سجّل الدخول برقمه المعرفي، أبقِ الشاشة مضاءة، وتأكد أن NFC مفعّل.';
    }
    if (r.uid != null) {
      return 'بطاقة NFC قُرئت ✔\nمعرّف الشريحة: ${r.uid}\nاربطها بالطالب من: الطلاب ← الطالب ← ربط بطاقة NFC (أو من المحاضرة مباشرة).';
    }
    return 'تعذّرت القراءة: ${r.info}';
  }

  @override
  Widget build(BuildContext context) {
    final r = _last;
    return Scaffold(
      appBar: gradientAppBar('اختبار NFC'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                  _available == true ? Icons.nfc : Icons.portable_wifi_off,
                  color: _available == true
                      ? AppColors.emerald
                      : AppColors.rose),
              title: Text(_available == null
                  ? 'جارٍ الفحص…'
                  : _available!
                      ? 'NFC مفعّل على هذا الهاتف'
                      : 'NFC غير متاح أو مطفأ'),
              subtitle: _available == false
                  ? const Text(
                      'فعّله من: الإعدادات ← الاتصالات ← NFC، ثم اضغط «إعادة الفحص». بعض الهواتف لا تحتوي شريحة NFC أصلاً.')
                  : null,
              trailing: TextButton(
                  onPressed: _check, child: const Text('إعادة الفحص')),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _waiting || _available != true ? null : _read,
            icon: _waiting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.contactless_rounded),
            label: Text(_waiting
                ? 'قرّب البطاقة أو الهاتف الآن…'
                : 'بدء الاختبار'),
          ),
          if (_timedOut)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text(
                  'لم يُكتشف أي شيء خلال 40 ثانية. جرّب تحريك البطاقة ببطء على ظهر الهاتف (مكان الشريحة غالباً قرب الكاميرا أو في المنتصف). إن لم يُكتشف شيء أبداً فالبطاقة غالباً لا تحتوي شريحة NFC.',
                  style: TextStyle(color: AppColors.orange)),
            ),
          if (r != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_verdict(r),
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, height: 1.7)),
                  const Divider(height: 24),
                  const Text('التفاصيل الفنية (أرسلها للدعم إن استمرت المشكلة):',
                      style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 6),
                  SelectableText(r.info,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12)),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: r.info));
                      showSnack(context, 'نُسخت التفاصيل');
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('نسخ'),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text('للتسجيل بهاتف الطالب:',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const Text(
              '• يجب أن يكون التطبيق مثبتاً على هاتف الطالب ومسجَّل الدخول بحسابه.\n'
              '• NFC مفعّل على الهاتفين، وشاشة هاتف الطالب مضاءة.\n'
              '• قرّب ظهر الهاتفين وثبّتهما ثانيتين.\n'
              '• هواتف iPhone لا تدعم هذه الخاصية؛ يستخدم الطالب رمز QR أو رقمه.',
              style: TextStyle(height: 1.8)),
          const SizedBox(height: 12),
          const Text('للبطاقة الجامعية:',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const Text(
              '• تعمل فقط إذا كانت البطاقة تحتوي شريحة NFC (البطاقة المطبوعة العادية لا تُقرأ).\n'
              '• تُربط البطاقة بالطالب مرة واحدة، ثم تُقرأ في كل محاضرة.',
              style: TextStyle(height: 1.8)),
        ],
      ),
    );
  }
}
