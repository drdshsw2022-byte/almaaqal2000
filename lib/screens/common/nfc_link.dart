import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../services/nfc_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// ربط شريحة NFC في الهوية الجامعية بطالب: يُطلب تقريب البطاقة من الهاتف.
Future<bool> linkNfcCard(BuildContext context, Student s) async {
  if (!await NfcService.isAvailable()) {
    if (context.mounted) {
      showSnack(context, 'هذا الهاتف لا يدعم NFC أو أنه مطفأ من الإعدادات',
          error: true);
    }
    return false;
  }
  if (!context.mounted) return false;
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
                color: AppColors.royal.withOpacity(0.1),
                shape: BoxShape.circle),
            child: const Icon(Icons.nfc, size: 56, color: AppColors.royal),
          ),
          const SizedBox(height: 14),
          Text('قرّب بطاقة ${s.name} من ظهر الهاتف',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            NfcService.cancelOne();
          },
          child: const Text('إلغاء'),
        ),
      ],
    ),
  );
  final uid = await NfcService.readOneUid();
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  await dialog;
  if (uid == null || !context.mounted) return false;
  final r = await runBusy(context, () async {
    await repo.setStudentNfc(s.id, uid);
    return true;
  }, success: 'تم ربط البطاقة بـ ${s.name}');
  return r == true;
}
