import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../services/excel_import.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// إدخال البيانات برفع ملفات Excel (لكل فقرة قالبها)، حسب صلاحية المستخدم.
class ImportScreen extends StatelessWidget {
  const ImportScreen({super.key});

  List<ImportKind> _kinds(Role r) => switch (r) {
        Role.admin || Role.president => ImportKind.values,
        Role.dean ||
        Role.head =>
          [ImportKind.students, ImportKind.staff, ImportKind.courses],
        _ => const [],
      };

  static const _desc = {
    ImportKind.structure:
        'الكلية، القسم، رمز القسم. يُنشئ الكليات والأقسام الجديدة ويحدّث الموجودة.',
    ImportKind.students:
        'الرقم المعرفي، الاسم، القسم، المرحلة، الدوام، البريد الجامعي. يقبل أيضاً ملف الطلاب الأصلي كما هو.',
    ImportKind.staff:
        'البريد الجامعي، الاسم، الصفة (رئاسة / عميد / رئيس قسم / تدريسي)، الكلية، القسم.',
    ImportKind.courses:
        'القسم، المرحلة، الكورس، رمز المقرر، الاسم، الساعات المعتمدة، ECTS، المتطلب السابق. يقبل ملف Resources الأصلي.',
  };

  static const _icons = {
    ImportKind.structure: Icons.account_balance_rounded,
    ImportKind.students: Icons.school_rounded,
    ImportKind.staff: Icons.badge_rounded,
    ImportKind.courses: Icons.auto_stories_rounded,
  };

  Future<void> _upload(BuildContext context, ImportKind k) async {
    List<(int, Map<String, String>)>? recs;
    try {
      recs = await ExcelImporter.pickRecords(k);
    } catch (e) {
      if (context.mounted) {
        showSnack(context, 'تعذّرت قراءة الملف: ${friendlyError(e)}',
            error: true);
      }
      return;
    }
    if (recs == null || !context.mounted) return;
    if (recs.isEmpty) {
      showSnack(context,
          'لم أجد صف عناوين مطابقاً في الملف. استخدم القالب الجاهز لهذه الفقرة.',
          error: true);
      return;
    }
    final ok = await confirmDialog(context, 'رفع ${importKindName(k)}',
        'وُجد ${recs.length} صفاً في الملف. سيُضاف الجديد ويُحدَّث الموجود (لا يُحذف شيء). متابعة؟',
        ok: 'رفع');
    if (!ok || !context.mounted) return;
    final res =
        await runBusy(context, () => ExcelImporter.run(k, recs!));
    if (res == null || !context.mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('نتيجة الرفع'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _num('جديد', res.added, AppColors.emerald),
                  _num('محدَّث', res.updated, AppColors.royal),
                  _num('مرفوض', res.skipped, AppColors.rose),
                ],
              ),
              if (res.errors.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('الصفوف المرفوضة:',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView(
                    shrinkWrap: true,
                    children: res.errors
                        .map((e) => Text('• $e',
                            style: const TextStyle(fontSize: 12)))
                        .toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
              onPressed: () => Navigator.pop(c), child: const Text('تم')),
        ],
      ),
    );
    if (k == ImportKind.structure) await AppState.refreshScope();
  }

  Widget _num(String l, int n, Color c) => Expanded(
        child: Column(
          children: [
            Text('$n',
                style: TextStyle(
                    color: c, fontSize: 24, fontWeight: FontWeight.w900)),
            Text(l, style: const TextStyle(color: AppColors.muted)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final role = AppState.user.value?.staff?.roleEnum ?? Role.doctor;
    final kinds = _kinds(role);
    return Scaffold(
      appBar: gradientAppBar('إدخال البيانات من Excel'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.royal.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              'نزّل القالب الخاص بكل فقرة، واملأه، ثم ارفعه. يُقبل أي ترتيب للأعمدة طالما كانت العناوين مطابقة. '
              'صلاحيتك: ${roleName(AppState.user.value?.staff?.role ?? '')}'
              '${AppState.scope.isAll ? ' (كل الجامعة)' : ' (ضمن نطاقك فقط)'}.',
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
          const SizedBox(height: 12),
          ...kinds.asMap().entries.map((e) {
            final k = e.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: AppColors.tilePalette[
                              e.key % AppColors.tilePalette.length],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(_icons[k], color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(importKindName(k),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(_desc[k]!,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12.5, height: 1.6)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44)),
                          onPressed: () => ExcelImporter.shareTemplate(k),
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('القالب'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44)),
                          onPressed: () => _upload(context, k),
                          icon: const Icon(Icons.upload_file_rounded),
                          label: const Text('رفع ملف'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
