import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// تغيير كلمة المرور (إجباري عند أول دخول بكلمة المرور الأولية).
class ChangePasswordScreen extends StatefulWidget {
  final bool force;
  const ChangePasswordScreen({super.key, this.force = false});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _new2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_new.text.length < 8) {
      showSnack(context, 'كلمة المرور الجديدة 8 أحرف على الأقل', error: true);
      return;
    }
    if (_new.text != _new2.text) {
      showSnack(context, 'كلمتا المرور غير متطابقتين', error: true);
      return;
    }
    if (_new.text == _old.text) {
      showSnack(context, 'اختر كلمة مرور مختلفة عن الحالية', error: true);
      return;
    }
    final ok = await runBusy(context, () async {
      await repo.changePassword(_old.text, _new.text);
      return true;
    }, success: 'تم تغيير كلمة المرور');
    if (ok != true || !mounted) return;
    if (widget.force) {
      AppState.mustChangePassword.value = false;
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = AppState.user.value;
    return Scaffold(
      appBar: gradientAppBar(
        widget.force ? 'تعيين كلمة مرور جديدة' : 'تغيير كلمة المرور',
        actions: [
          if (widget.force)
            IconButton(
              onPressed: () async {
                await repo.signOut();
                AppState.mustChangePassword.value = false;
                AppState.user.value = null;
              },
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.force)
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.gold.withOpacity(0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                'مرحباً ${u?.name ?? ''}. هذا أول دخول لك بكلمة المرور الأولية، ولحماية حسابك اختر كلمة مرور خاصة بك.',
                style: const TextStyle(height: 1.6),
              ),
            ),
          TextField(
            controller: _old,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: widget.force
                  ? 'كلمة المرور الأولية'
                  : 'كلمة المرور الحالية',
              prefixIcon: const Icon(Icons.lock_clock_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _new,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'كلمة المرور الجديدة (8 أحرف فأكثر)',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(_obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _new2,
            obscureText: _obscure,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(
              labelText: 'تأكيد كلمة المرور الجديدة',
              prefixIcon: Icon(Icons.lock_reset),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.check),
            label: const Text('حفظ كلمة المرور'),
          ),
        ],
      ),
    );
  }
}
