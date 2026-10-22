import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  final Future<void> Function() onSeed;
  const SettingsScreen({super.key, required this.onSeed});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _term;
  late double _warn;
  late double _fail;

  @override
  void initState() {
    super.initState();
    final s = AppState.settings;
    _term = s.currentTerm;
    _warn = s.warnPercent;
    _fail = s.failPercent;
  }

  Future<void> _save() async {
    if (_warn >= _fail) {
      showSnack(context, 'نسبة الإنذار يجب أن تكون أقل من نسبة الحرمان',
          error: true);
      return;
    }
    final s =
        AppSettings(currentTerm: _term, warnPercent: _warn, failPercent: _fail);
    final r = await runBusy(context, () async {
      await repo.saveSettings(s);
      return true;
    }, success: 'تم حفظ الإعدادات');
    if (r == true) AppState.settings = s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar('الإعدادات'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card(
            icon: Icons.calendar_month,
            title: 'الفصل الدراسي الحالي',
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('الفصل الأول')),
                ButtonSegment(value: 2, label: Text('الفصل الثاني')),
              ],
              selected: {_term},
              onSelectionChanged: (v) => setState(() => _term = v.first),
            ),
          ),
          _card(
            icon: Icons.warning_amber_rounded,
            title: 'نسبة الإنذار: ${_warn.round()}%',
            child: Slider(
              value: _warn,
              min: 1,
              max: 50,
              divisions: 49,
              activeColor: AppColors.orange,
              label: '${_warn.round()}%',
              onChanged: (v) => setState(() => _warn = v),
            ),
          ),
          _card(
            icon: Icons.block,
            title: 'نسبة الحرمان: ${_fail.round()}%',
            child: Slider(
              value: _fail,
              min: 2,
              max: 60,
              divisions: 58,
              activeColor: AppColors.rose,
              label: '${_fail.round()}%',
              onChanged: (v) => setState(() => _fail = v),
            ),
          ),
          const SizedBox(height: 6),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ الإعدادات'),
          ),
          const SectionTitle('البيانات'),
          _card(
            icon: Icons.cloud_sync,
            title: 'تهيئة / تحديث قاعدة البيانات',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'رفع الكليات والأقسام والمواد والطلاب من الملفات المرفقة بالتطبيق (Students و Resources). لا تُحذف التعديلات السابقة على أقسام الطلاب أو حساباتهم.',
                  style: TextStyle(color: AppColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: widget.onSeed,
                  icon: const Icon(Icons.upload),
                  label: const Text('تشغيل التهيئة'),
                ),
              ],
            ),
          ),
          _card(
            icon: Icons.info_outline,
            title: 'معلومات',
            child: Text(
              'وضع التشغيل: ${repo.isDemo ? 'تجريبي محلي (جهاز واحد)' : 'Firebase (متعدد الأجهزة)'}\n'
              'طرق التسجيل: مسح QR لهوية الطالب، أو NFC (بطاقة أو هاتف)\n'
              'الإصدار 1.0.0',
              style: const TextStyle(color: AppColors.muted, height: 1.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(
      {required IconData icon, required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.royal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
