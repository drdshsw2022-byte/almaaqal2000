import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// تصفّح المواد بالتسلسل: القسم ← المرحلة ← الكورس (الأول/الثاني) ← المواد.
class CourseBrowser extends StatefulWidget {
  final List<Course> courses;
  final List<Department> departments;
  final Widget Function(BuildContext context, Course c) itemBuilder;
  final String? initialDept;
  final int? initialStage;
  final int initialTerm;

  /// عدد مميَّز يظهر على بطاقات القسم/المرحلة (مثل عدد المواد المختارة).
  final int Function(Iterable<Course> courses)? badge;

  /// يُستدعى عند تغيّر المستوى الحالي.
  final void Function(String? dept, int? stage, int term)? onChanged;

  /// شريط أدوات فوق قائمة المواد (مثل "تحديد الكل").
  final Widget Function(List<Course> visible)? listHeader;

  const CourseBrowser({
    super.key,
    required this.courses,
    required this.departments,
    required this.itemBuilder,
    this.initialDept,
    this.initialStage,
    this.initialTerm = 1,
    this.badge,
    this.onChanged,
    this.listHeader,
  });

  @override
  State<CourseBrowser> createState() => _CourseBrowserState();
}

class _CourseBrowserState extends State<CourseBrowser> {
  String? _dept;
  int? _stage;
  late int _term;

  @override
  void initState() {
    super.initState();
    _dept = widget.initialDept;
    _stage = _dept == null ? null : widget.initialStage;
    _term = widget.initialTerm;
  }

  void _set({String? dept, int? stage, int? term, bool up = false}) {
    setState(() {
      if (up) {
        if (_stage != null) {
          _stage = null;
        } else {
          _dept = null;
        }
      } else {
        if (dept != null) _dept = dept;
        if (stage != null) _stage = stage;
        if (term != null) _term = term;
      }
    });
    widget.onChanged?.call(_dept, _stage, _term);
  }

  String _deptName(String id) =>
      widget.departments.where((d) => d.id == id).map((d) => d.name).firstOrNull ??
      id;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _dept == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _set(up: true);
      },
      child: Column(
        children: [
          _breadcrumb(),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _dept == null
                  ? _deptGrid()
                  : _stage == null
                      ? _stageList()
                      : _courseList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _breadcrumb() {
    Widget crumb(String t, VoidCallback? onTap, bool last) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Text(t,
                style: TextStyle(
                    fontWeight: last ? FontWeight.w800 : FontWeight.w500,
                    color: last ? AppColors.royal : AppColors.muted)),
          ),
        );
    final items = <Widget>[
      crumb('الأقسام', _dept == null ? null : () => setState(() {
            _dept = null;
            _stage = null;
            widget.onChanged?.call(null, null, _term);
          }), _dept == null),
    ];
    if (_dept != null) {
      items.add(const Icon(Icons.chevron_right, size: 18, color: AppColors.muted));
      items.add(crumb(_deptName(_dept!), _stage == null ? null : () => _set(up: true),
          _stage == null));
    }
    if (_stage != null) {
      items.add(const Icon(Icons.chevron_right, size: 18, color: AppColors.muted));
      items.add(crumb(stageName(_stage!), null, true));
    }
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: items),
      ),
    );
  }

  Widget _badge(Iterable<Course> cs) {
    final n = widget.badge?.call(cs) ?? 0;
    if (n == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: AppColors.gold, borderRadius: BorderRadius.circular(12)),
      child: Text('$n',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
    );
  }

  Widget _deptGrid() {
    final depts = widget.departments.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (depts.isEmpty) {
      return const EmptyState(icon: Icons.apartment, text: 'لا توجد أقسام');
    }
    return ListView(
      key: const ValueKey('depts'),
      padding: const EdgeInsets.all(16),
      children: [
        for (var i = 0; i < depts.length; i++)
          Builder(builder: (context) {
            final d = depts[i];
            final cs = widget.courses.where((c) => c.deptId == d.id);
            final stages = cs.map((c) => c.stage).toSet().length;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => _set(dept: d.id),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: AppColors.tilePalette[
                                i % AppColors.tilePalette.length],
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.apartment_rounded,
                              color: Colors.white, size: 30),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16)),
                              Text('$stages مراحل • ${cs.length} مادة',
                                  style: const TextStyle(
                                      color: AppColors.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                        _badge(cs),
                        const SizedBox(width: 6),
                        const Icon(Icons.chevron_right, color: AppColors.muted),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _stageList() {
    final cs = widget.courses.where((c) => c.deptId == _dept).toList();
    final stages = cs.map((c) => c.stage).toSet().toList()..sort();
    if (stages.isEmpty) {
      return const EmptyState(icon: Icons.stairs, text: 'لا توجد مواد لهذا القسم');
    }
    return GridView.count(
      key: ValueKey('stages-$_dept'),
      padding: const EdgeInsets.all(16),
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.25,
      children: stages.map((st) {
        final sc = cs.where((c) => c.stage == st);
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () => _set(stage: st),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: AppColors.tilePalette[
                              (st - 1) % AppColors.tilePalette.length],
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Text('$st',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900)),
                      ),
                      const Spacer(),
                      _badge(sc),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stageName(st),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      Text(
                          'الكورس الأول ${sc.where((c) => c.term == 1).length} • الثاني ${sc.where((c) => c.term == 2).length}',
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _courseList() {
    final list = widget.courses
        .where((c) => c.deptId == _dept && c.stage == _stage && c.term == _term)
        .toList()
      ..sort((a, b) => a.nameAr.compareTo(b.nameAr));
    return Column(
      key: ValueKey('courses-$_dept-$_stage'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('الكورس الأول')),
                ButtonSegment(value: 2, label: Text('الكورس الثاني')),
              ],
              selected: {_term},
              onSelectionChanged: (v) => _set(term: v.first),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
          child: Row(
            children: [
              Text(
                  '${_deptName(_dept!)} • ${stageName(_stage!)} • ${termName(_term)}',
                  style: const TextStyle(
                      color: AppColors.muted, fontSize: 12)),
              const Spacer(),
              Text('${list.length} مادة',
                  style: const TextStyle(
                      color: AppColors.royal, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        if (widget.listHeader != null) widget.listHeader!(list),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.menu_book, text: 'لا توجد مواد في هذا الكورس')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 90),
                  itemCount: list.length,
                  itemBuilder: (ctx, i) => widget.itemBuilder(ctx, list[i]),
                ),
        ),
      ],
    );
  }
}
