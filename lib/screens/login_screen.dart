import 'package:flutter/material.dart';

import '../app_state.dart';
import '../config.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// الدخول: اسم المستخدم/الرقم المعرفي وكلمة المرور، أو حساب Google الجامعي.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pw = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  Portal _portal = Portal.management;

  static const _tabs = [
    (Portal.management, 'الإدارة', Icons.account_balance_rounded),
    (Portal.teacher, 'التدريسي', Icons.co_present_rounded),
    (Portal.student, 'الطالب', Icons.school_rounded),
  ];

  /// هل يطابق الحساب التبويب المختار؟
  String? _mismatch(AppUser u) {
    switch (_portal) {
      case Portal.management:
        return isManagement(u.role)
            ? null
            : 'هذا الحساب ليس من الإدارة؛ ادخل من تبويب "${u.role == Role.student ? 'الطالب' : 'التدريسي'}"';
      case Portal.teacher:
        return (u.role == Role.doctor ||
                u.role == Role.head ||
                u.role == Role.dean)
            ? null
            : (u.role == Role.student
                ? 'هذا حساب طالب؛ ادخل من تبويب "الطالب"'
                : 'هذا الحساب إداري؛ ادخل من تبويب "الإدارة"');
      case Portal.student:
        return u.role == Role.student
            ? null
            : 'هذا الحساب ليس حساب طالب؛ ادخل من تبويب "${isManagement(u.role) ? 'الإدارة' : 'التدريسي'}"';
    }
  }

  @override
  void dispose() {
    _user.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _finish(AppUser u, bool mustChange) async {
    final why = _mismatch(u);
    if (why != null) {
      await repo.signOut();
      throw AppException(why);
    }
    await AppState.savePortal(_portal);
    AppState.mustChangePassword.value = mustChange;
    await AppState.afterLogin(u);
  }

  Future<void> _signInPassword() async {
    final user = _user.text.trim();
    if (user.isEmpty) {
      showSnack(
          context,
          _portal == Portal.student
              ? 'خانة الرقم المعرفي فارغة'
              : 'خانة اسم المستخدم فارغة',
          error: true);
      return;
    }
    if (_pw.text.isEmpty) {
      showSnack(context, 'خانة كلمة المرور فارغة', error: true);
      return;
    }
    if (_portal == Portal.student && !RegExp(r'^[0-9]+$').hasMatch(user)) {
      showSnack(context, 'الرقم المعرفي أرقام فقط', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await repo.signInWithPassword(user, _pw.text);
      await _finish(r.user, r.mustChangePassword);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInGoogle({bool superAdmin = false}) async {
    setState(() => _busy = true);
    try {
      final u = await repo.signInWithGoogle(
          demoEmail: superAdmin ? 'superadmin' : null);
      await _finish(u, false);
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.mainGradient),
        child: Stack(
          children: [
            Positioned(
              top: -60,
              left: -60,
              child: _glow(220, AppColors.cyan.withOpacity(0.25)),
            ),
            Positioned(
              bottom: -80,
              right: -40,
              child: _glow(260, AppColors.gold.withOpacity(0.18)),
            ),
            ListView(
              padding: EdgeInsets.fromLTRB(22, top + 40, 22, 30),
              children: [
                const Center(child: AppLogo(size: 108)),
                const SizedBox(height: 18),
                const Text(AppConfig.universityName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 27,
                        fontWeight: FontWeight.w900)),
                Text('${AppConfig.city} • النظام الجامعي المتكامل',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.8), fontSize: 14)),
                const SizedBox(height: 30),
                _card(),
                if (repo.isDemo) ...[
                  const SizedBox(height: 16),
                  _localBanner(),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _card() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 30,
              offset: const Offset(0, 14))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _tabBar(),
          const SizedBox(height: 18),
          Text('دخول ${_tabs.firstWhere((t) => t.$1 == _portal).$2}',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          TextField(
            controller: _user,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: _portal == Portal.student
                ? TextInputType.number
                : TextInputType.text,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: _portal == Portal.student
                  ? 'الرقم المعرفي (الجامعي)'
                  : 'اسم المستخدم',
              prefixIcon: Icon(_portal == Portal.student
                  ? Icons.badge_outlined
                  : Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _pw,
            obscureText: _obscure,
            onSubmitted: (_) => _signInPassword(),
            decoration: InputDecoration(
              labelText: 'كلمة المرور',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 18),
          _loginButton(),
          if (!repo.isDemo) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('أو',
                      style: TextStyle(color: Colors.grey.shade500)),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _signInGoogle(),
              icon: const _GoogleMark(),
              label: const Text('بحساب Google الجامعي'),
            ),
            if (_portal == Portal.management)
              TextButton(
                onPressed: _busy ? null : () => _signInGoogle(superAdmin: true),
                child: const Text('دخول المدير العام بحساب آخر',
                    style: TextStyle(fontSize: 12)),
              ),
          ],
          const SizedBox(height: 6),
          Text(
            _portal == Portal.student
                ? 'أول دخول: كلمة المرور الأولية هي رقمك المعرفي، وسيُطلب منك تغييرها.'
                : 'أول دخول: استخدم كلمة المرور الأولية التي سلّمتها لك الإدارة، وسيُطلب منك تغييرها.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _tabBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F2F9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: _tabs.map((t) {
          final on = t.$1 == _portal;
          return Expanded(
            child: GestureDetector(
              onTap: _busy ? null : () => setState(() => _portal = t.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: on ? AppColors.mainGradient : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Icon(t.$3,
                        size: 22, color: on ? Colors.white : AppColors.muted),
                    const SizedBox(height: 2),
                    Text(t.$2,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: on ? Colors.white : AppColors.muted)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _loginButton() {
    return Opacity(
      opacity: _busy ? 0.6 : 1,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            gradient: AppColors.mainGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _busy ? null : _signInPassword,
            child: Center(
              child: _busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))
                  : const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.login, color: Colors.white),
                        SizedBox(width: 8),
                        Text('تسجيل الدخول',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _localBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_off, color: AppColors.gold, size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'غير متصل بخادم الجامعة بعد: البيانات محفوظة على هذا الجهاز فقط.',
              style: TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(double s, Color c) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c),
      );
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [
          Color(0xFFEA4335),
          Color(0xFFFBBC05),
          Color(0xFF34A853),
          Color(0xFF4285F4),
          Color(0xFFEA4335),
        ]),
      ),
      child: const Text('G',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              height: 1.1)),
    );
  }
}
