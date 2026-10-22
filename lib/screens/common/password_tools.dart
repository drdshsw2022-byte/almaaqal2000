import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../config.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// إعادة حساب طالب أو عضو كادر إلى كلمة مرور أولية (للإدارة).
Future<void> resetPasswordFlow(BuildContext context,
    {Student? student, Staff? staff}) async {
  final ctrl = TextEditingController();
  final isStudent = student != null;
  final name = student?.name ?? staff!.name;
  final username = student?.id ?? staff!.loginName;
  final authName = student?.id ?? (staff!.alias ?? staff!.username);
  final def = isStudent ? 'الرقم المعرفي ($username)' : AppConfig.defaultStaffPassword;
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('إعادة تعيين كلمة المرور'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name\nاسم المستخدم: $username',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: 'كلمة مرور أولية جديدة (اختياري)',
                helperText: 'اتركه فارغاً لاستخدام الافتراضية: $def',
                helperMaxLines: 2,
              ),
            ),
            if (!repo.isDemo) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.gold.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'خطوة إضافية مطلوبة في Firebase Console ← Authentication: احذف المستخدم '
                  '${isStudent ? '$authName@${AppConfig.studentAuthDomain}' : '$authName@${AppConfig.staffAuthDomain}'} '
                  'حتى يتمكن من الدخول بكلمة المرور الأولية.',
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('إعادة التعيين')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final pw = ctrl.text.trim().isEmpty ? null : ctrl.text.trim();
  if (pw != null && pw.length < 6) {
    showSnack(context, 'كلمة المرور الأولية 6 أحرف على الأقل', error: true);
    return;
  }
  await runBusy(
    context,
    () => isStudent
        ? repo.resetStudentAccount(student!.id, initPw: pw)
        : repo.resetStaffAccount(staff!.id, initPw: pw),
    success: 'تمت إعادة التعيين. كلمة المرور الأولية: ${pw ?? def}',
  );
}
