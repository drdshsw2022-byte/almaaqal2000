import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'course_browser.dart';

/// اختيار مواد (متعدد أو مفرد) بالتسلسل: القسم ← المرحلة ← الكورس ← المواد.
class CoursePickerScreen extends StatefulWidget {
  final Set<String> initial;
  final bool multi;
  final String title;
  final String? initialDept;

  /// في الوضع المفرد: إن وُجد يُستدعى بدلاً من إغلاق الصفحة.
  final void Function(BuildContext context, Course course)? onPicked;

  const CoursePickerScreen({
    super.key,
    this.initial = const {},
    this.multi = true,
    this.title = 'اختيار المواد',
    this.initialDept,
    this.onPicked,
  });

  @override
  State<CoursePickerScreen> createState() => _CoursePickerScreenState();
}

class _CoursePickerScreenState extends State<CoursePickerScreen> {
  late Set<String> _sel;
  List<Course> _all = [];
  List<Department> _depts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _sel = {...widget.initial};
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([repo.courses(), repo.departments()]);
      // الإدارة ترى نطاقها فقط؛ التدريسي يرى كل المواد (قد يدرّس في أقسام أخرى)
      final u = AppState.user.value;
      final scoped = u != null && isManagement(u.role);
      final scope = AppState.scope;
      _all = (r[0] as List<Course>)
          .where((c) => !scoped || scope.hasDept(c.deptId))
          .toList();
      _depts = scoped
          ? scope.filterDepts(r[1] as List<Department>)
          : r[1] as List<Department>;
    } catch (e) {
      if (mounted) showSnack(context, friendlyError(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: gradientAppBar(widget.title),
      bottomNavigationBar: widget.multi
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context, _sel.toList()),
                  icon: const Icon(Icons.check),
                  label: Text('حفظ (${_sel.length} مادة)'),
                ),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CourseBrowser(
              courses: _all,
              departments: _depts,
              initialDept: widget.initialDept,
              initialTerm: AppState.settings.currentTerm,
              badge: widget.multi
                  ? (cs) => cs.where((c) => _sel.contains(c.id)).length
                  : null,
              listHeader: widget.multi
                  ? (visible) {
                      final all = visible.isNotEmpty &&
                          visible.every((c) => _sel.contains(c.id));
                      return Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: TextButton.icon(
                            onPressed: visible.isEmpty
                                ? null
                                : () => setState(() => all
                                    ? _sel.removeAll(visible.map((c) => c.id))
                                    : _sel.addAll(visible.map((c) => c.id))),
                            icon: Icon(all ? Icons.deselect : Icons.select_all),
                            label: Text(all ? 'إلغاء الكل' : 'تحديد الكل'),
                          ),
                        ),
                      );
                    }
                  : null,
              itemBuilder: (ctx, c) {
                final on = _sel.contains(c.id);
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: widget.multi
                      ? CheckboxListTile(
                          value: on,
                          activeColor: AppColors.royal,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          onChanged: (v) => setState(() =>
                              v == true ? _sel.add(c.id) : _sel.remove(c.id)),
                          title: Text(c.nameAr,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${c.code} • ${c.ects} ECTS',
                              style: const TextStyle(fontSize: 12)),
                        )
                      : ListTile(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                          onTap: () => widget.onPicked != null
                              ? widget.onPicked!(ctx, c)
                              : Navigator.pop(context, [c.id]),
                          title: Text(c.nameAr,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${c.code} • ${c.ects} ECTS',
                              style: const TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                );
              },
            ),
    );
  }
}
