import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/repo.dart';
import 'models.dart';

/// بوابة الدخول المختارة من تبويبات شاشة الدخول.
enum Portal { management, teacher, student }

/// نطاق صلاحيات المستخدم: الأقسام والكليات التي يحق له رؤيتها وإدارتها.
class Scope {
  final Set<String>? deptIds; // null = كل الأقسام
  final Set<String>? collegeIds; // null = كل الكليات
  const Scope.all()
      : deptIds = null,
        collegeIds = null;
  const Scope(this.deptIds, this.collegeIds);

  bool get isAll => deptIds == null;
  bool hasDept(String? id) =>
      deptIds == null || (id != null && deptIds!.contains(id));
  bool hasCollege(String? id) =>
      collegeIds == null || (id != null && collegeIds!.contains(id));

  List<Department> filterDepts(List<Department> all) =>
      all.where((d) => hasDept(d.id)).toList();
}

/// حالة التطبيق العامة (المستخدم الحالي ومصدر البيانات).
class AppState {
  AppState._();
  static late Repo repo;
  static final ValueNotifier<AppUser?> user = ValueNotifier<AppUser?>(null);

  /// يجب تغيير كلمة المرور الأولية قبل استخدام التطبيق.
  static final ValueNotifier<bool> mustChangePassword = ValueNotifier(false);
  static AppSettings settings = const AppSettings();
  static Scope scope = const Scope.all();
  static Portal portal = Portal.management;

  static const _portalKey = 'portal';

  static Future<void> refreshSettings() async {
    try {
      settings = await repo.settings();
    } catch (_) {}
  }

  static Future<void> savePortal(Portal p) async {
    portal = p;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_portalKey, p.name);
    } catch (_) {}
  }

  static Future<void> loadPortal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_portalKey);
      portal = Portal.values.where((p) => p.name == v).firstOrNull ??
          Portal.management;
    } catch (_) {}
  }

  /// يحسب نطاق الصلاحيات حسب الصفة.
  static Future<void> refreshScope([AppUser? forUser]) async {
    final u = forUser ?? user.value;
    final st = u?.staff;
    if (st == null) {
      scope = const Scope({}, {});
      return;
    }
    switch (st.roleEnum) {
      case Role.admin:
      case Role.president:
        scope = const Scope.all();
      case Role.dean:
        final depts = await repo.departments();
        final cid = st.collegeId;
        scope = Scope(
            depts.where((d) => d.collegeId == cid).map((d) => d.id).toSet(),
            {if (cid != null) cid});
      case Role.head:
      case Role.doctor:
        final depts = await repo.departments();
        final d = depts.where((x) => x.id == st.deptId).firstOrNull;
        scope = Scope({if (st.deptId != null) st.deptId!},
            {if (d != null) d.collegeId});
      case Role.student:
        scope = const Scope({}, {});
    }
  }

  /// بعد تسجيل الدخول: يحمّل الإعدادات والنطاق ثم يعرض الواجهة.
  static Future<void> afterLogin(AppUser u) async {
    await refreshSettings();
    try {
      await refreshScope(u);
    } catch (_) {}
    user.value = u;
  }
}

Repo get repo => AppState.repo;
