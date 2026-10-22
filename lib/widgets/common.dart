import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../services/nfc_service.dart';
import '../theme.dart';

/// شعار التطبيق.
class AppLogo extends StatelessWidget {
  final double size;
  final bool light; // النسخة الذهبية على خلفية بيضاء
  const AppLogo({super.key, this.size = 72, this.light = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: size * 0.2,
              offset: Offset(0, size * 0.06)),
        ],
      ),
      child: Image.asset(
          light ? 'assets/images/logo_light.png' : 'assets/images/logo.png',
          fit: BoxFit.contain),
    );
  }
}

/// ترويسة متدرجة للوحات التحكم.
class GradientHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> actions;
  final Widget? bottom;
  final IconData roleIcon;

  const GradientHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.bottom,
    this.roleIcon = Icons.person,
  });

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Container(
      decoration: const BoxDecoration(
        gradient: AppColors.mainGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
      ),
      child: Stack(
        children: [
          Positioned(
            left: -40,
            top: -30,
            child: _bubble(160, Colors.white.withOpacity(0.06)),
          ),
          Positioned(
            right: -30,
            bottom: -50,
            child: _bubble(140, AppColors.cyan.withOpacity(0.18)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, top + 12, 20, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AppLogo(size: 42),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(AppConfig.universityName,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                          Text('${AppConfig.city} • ${AppConfig.appName}',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.75),
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    ...actions,
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: AppColors.goldGradient,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(roleIcon, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800)),
                          Text(subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (bottom != null) ...[const SizedBox(height: 18), bottom!],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(double s, Color c) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c),
      );
}

/// شريط تطبيق متدرج للصفحات الداخلية.
PreferredSizeWidget gradientAppBar(String title,
    {List<Widget>? actions, PreferredSizeWidget? bottom}) {
  return AppBar(
    title: Text(title),
    actions: actions,
    bottom: bottom,
    flexibleSpace: Container(
      decoration: const BoxDecoration(gradient: AppColors.mainGradient),
    ),
  );
}

class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Gradient gradient;
  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withOpacity(0.35),
            blurRadius: 14,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(value,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                ),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.9), fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ActionTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;
  const ActionTile({
    super.key,
    required this.title,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  if (subtitle != null)
                    Text(subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 20,
            decoration: BoxDecoration(
              gradient: AppColors.goldGradient,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const EmptyState({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: AppColors.royal.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 44, color: AppColors.royal),
          ),
          const SizedBox(height: 14),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted, fontSize: 15)),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, {super.key, this.color = AppColors.royal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// حالة الطالب في مادة حسب نسبة الغياب.
({String label, Color color}) absenceStatus(double percent) {
  final s = AppState.settings;
  if (percent >= s.failPercent) {
    return (label: 'محروم', color: AppColors.rose);
  }
  if (percent >= s.warnPercent) {
    return (label: 'إنذار', color: AppColors.orange);
  }
  return (label: 'منتظم', color: AppColors.emerald);
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.rose : AppColors.night,
    ));
}

Future<bool> confirmDialog(BuildContext context, String title, String body,
    {String ok = 'تأكيد', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: danger ? AppColors.rose : AppColors.royal),
          onPressed: () => Navigator.pop(c, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r == true;
}

/// ينفذ عملية مع مؤشر انتظار ويعرض الخطأ إن وجد.
Future<T?> runBusy<T>(BuildContext context, Future<T> Function() task,
    {String? success}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
    ),
  );
  try {
    final r = await task();
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      if (success != null) showSnack(context, success);
    }
    return r;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      showSnack(context, friendlyError(e), error: true);
    }
    return null;
  }
}

String friendlyError(Object e) {
  if (e is AppException) return e.message;
  final s = e.toString();
  if (s.contains('ApiException: 10') || s.contains('sign_in_failed')) {
    return 'إعداد تسجيل الدخول بـ Google غير مكتمل (تحقق من بصمة SHA-1 في Firebase)';
  }
  if (s.contains('permission-denied')) {
    return 'لا تملك صلاحية لهذه العملية';
  }
  if (s.contains('unavailable') || s.contains('network')) {
    return 'تعذّر الاتصال بالخادم، تحقق من الإنترنت';
  }
  return s.replaceFirst('Exception: ', '');
}

String two(int n) => n.toString().padLeft(2, '0');
String fmtDate(DateTime d) => '${d.year}/${two(d.month)}/${two(d.day)}';
String fmtTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${two(d.minute)} ${d.hour < 12 ? 'ص' : 'م'}';
}

String fmtDateTime(DateTime d) => '${fmtDate(d)} • ${fmtTime(d)}';

const weekDays = [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد'
];
String dayName(DateTime d) => weekDays[d.weekday - 1];

/// تسجيل الخروج والرجوع لشاشة الدخول.
Future<void> logout(BuildContext context) async {
  final ok = await confirmDialog(
      context, 'تسجيل الخروج', 'هل تريد تسجيل الخروج من حسابك؟',
      ok: 'خروج');
  if (!ok) return;
  await AppState.repo.signOut();
  await NfcService.setStudentPayload(null);
  AppState.mustChangePassword.value = false;
  AppState.user.value = null;
}

class CircleProgress extends StatelessWidget {
  final double percent; // 0..100
  final Color color;
  final double size;
  const CircleProgress(
      {super.key, required this.percent, required this.color, this.size = 54});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: (percent / 100).clamp(0.0, 1.0).toDouble(),
              strokeWidth: 5,
              backgroundColor: color.withOpacity(0.12),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text('${percent.round()}%',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: size * 0.24,
                  color: color)),
        ],
      ),
    );
  }
}
