import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'change_password_screen.dart';

/// نافذة الملف الشخصي.
Future<void> showProfileSheet(BuildContext context) {
  final u = AppState.user.value!;
  final roleLabel = roleName(u.staff?.role ?? 'student');
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: AppColors.mainGradient,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Text(
                  u.name.isEmpty ? '?' : u.name.characters.first,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(u.name,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Center(child: Pill(roleLabel)),
            const SizedBox(height: 16),
            _row(Icons.person_outline, 'اسم المستخدم',
                u.student?.id ?? u.staff!.loginName),
            _row(Icons.alternate_email, 'البريد', u.email ?? '—'),
            if (u.student != null) ...[
              _row(Icons.badge_outlined, 'الرقم المعرفي', u.student!.id),
              _row(Icons.stairs_outlined, 'المرحلة',
                  stageName(u.student!.stage)),
              _row(Icons.wb_sunny_outlined, 'الدوام',
                  shiftName(u.student!.shift)),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(c);
                Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ChangePasswordScreen()));
              },
              icon: const Icon(Icons.password),
              label: const Text('تغيير كلمة المرور'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(c);
                logout(context);
              },
              icon: const Icon(Icons.logout),
              label: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _row(IconData i, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(i, color: AppColors.royal, size: 20),
          const SizedBox(width: 10),
          Text('$k: ', style: const TextStyle(color: AppColors.muted)),
          Expanded(
            child: Text(v,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
