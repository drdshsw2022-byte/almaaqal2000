import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';

/// شريط بحث وتصفية أعلى القوائم.
class FilterBar extends StatelessWidget {
  final String searchHint;
  final ValueChanged<String>? onSearch;
  final List<Widget> children;
  const FilterBar(
      {super.key,
      required this.searchHint,
      this.onSearch,
      this.children = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        children: [
          if (onSearch != null)
            TextField(
              onChanged: onSearch,
              decoration: InputDecoration(
                hintText: searchHint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          if (children.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: children.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => children[i],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// شريحة اختيار تفتح قائمة خيارات.
class ChoiceMenuChip<T> extends StatelessWidget {
  final String label;
  final T? value;
  final Map<T, String> options;
  final ValueChanged<T?> onChanged;
  final bool allowAll;

  const ChoiceMenuChip({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.allowAll = true,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value != null && options.containsKey(value);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.mainGradient : null,
          color: selected ? null : const Color(0xFFF1F2F9),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected ? '$label: ${options[value]}' : label,
              style: TextStyle(
                  color: selected ? Colors.white : AppColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13),
            ),
            const SizedBox(width: 2),
            Icon(Icons.expand_more,
                size: 18, color: selected ? Colors.white : AppColors.muted),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final r = await showModalBottomSheet<_Pick<T>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              if (allowAll)
                ListTile(
                  leading: Icon(value == null
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off),
                  title: const Text('الكل'),
                  onTap: () => Navigator.pop(c, _Pick<T>(null)),
                ),
              ...options.entries.map((e) => ListTile(
                    leading: Icon(
                        e.key == value
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: e.key == value ? AppColors.royal : null),
                    title: Text(e.value),
                    onTap: () => Navigator.pop(c, _Pick<T>(e.key)),
                  )),
            ],
          ),
        ),
      ),
    );
    if (r != null) onChanged(r.value);
  }
}

class _Pick<T> {
  final T? value;
  _Pick(this.value);
}

class DeptChip extends StatelessWidget {
  final List<Department> depts;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;
  const DeptChip(
      {super.key,
      required this.depts,
      required this.value,
      required this.onChanged,
      this.label = 'القسم'});

  @override
  Widget build(BuildContext context) {
    return ChoiceMenuChip<String>(
      label: label,
      value: value,
      options: {for (final d in depts) d.id: d.name},
      onChanged: onChanged,
    );
  }
}
