import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../app/session/app_cubit.dart';
import '../../../core/network/json.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/widgets.dart';
import '../cubit/profile_form_cubit.dart';

/// Personal details form: name and mobile are required, address is optional,
/// email is the sign-in identity so it is shown read-only.
/// Used after first sign-in and from Profile › Edit details.
class ProfileForm extends StatelessWidget {
  final String submitLabel;
  final VoidCallback onSaved;
  final bool showHandle;
  const ProfileForm({super.key, required this.submitLabel, required this.onSaved, this.showHandle = false});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (c) => ProfileFormCubit(app: c.read<AppCubit>()),
    child: _ProfileFormView(submitLabel: submitLabel, onSaved: onSaved, showHandle: showHandle),
  );
}

class _ProfileFormView extends StatefulWidget {
  final String submitLabel;
  final VoidCallback onSaved;
  final bool showHandle;
  const _ProfileFormView({required this.submitLabel, required this.onSaved, required this.showHandle});

  @override
  State<_ProfileFormView> createState() => _ProfileFormViewState();
}

class _ProfileFormViewState extends State<_ProfileFormView> {
  late final Json u = context.read<AppCubit>().state.user ?? {};
  late final name = TextEditingController(text: u['name'] ?? '');
  late final phone = TextEditingController(text: _localPhone(u['phone']));
  late final address = TextEditingController(text: u['address'] ?? '');
  late final handle = TextEditingController(text: u['handle'] ?? '');
  static String _localPhone(String? p) {
    final digits = (p ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.length == 12 && digits.startsWith('91') ? digits.substring(2) : digits;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final saved = await context.read<ProfileFormCubit>().save(
      name: name.text,
      phone: phone.text,
      address: address.text,
      handle: widget.showHandle ? handle.text : null,
    );
    if (saved) widget.onSaved();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ProfileFormCubit, ProfileFormState>(builder: _build);

  Widget _build(BuildContext context, ProfileFormState st) {
    final errors = st.errors, busy = st.busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(
          name,
          'Full name',
          'e.g. Arjun Mehta',
          errors['name'],
          type: TextInputType.name,
          caps: TextCapitalization.words,
          autofill: AutofillHints.name,
        ),
        _readOnly('Email', u['email'] ?? ''),
        _field(
          phone,
          'Mobile number',
          '98765 43210',
          errors['phone'],
          type: TextInputType.phone,
          prefix: '+91',
          autofill: AutofillHints.telephoneNumberNational,
          formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
          help: 'Shared only with the venue you book.',
        ),
        _field(
          address,
          'Address',
          'House, street, area, city',
          null,
          optional: true,
          type: TextInputType.streetAddress,
          caps: TextCapitalization.sentences,
          lines: 2,
          autofill: AutofillHints.fullStreetAddress,
        ),
        if (widget.showHandle) _field(handle, 'Handle', 'arjun.plays', null, optional: true, prefix: '@'),
        if (errors['form'] != null)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.warnBg, borderRadius: BorderRadius.circular(12)),
            child: Text(errors['form']!, style: t(13, c: C.warnInk, h: 1.4)),
          ),
        const SizedBox(height: 4),
        PrimaryButton(widget.submitLabel, height: 52, loading: busy, onTap: _save),
      ],
    );
  }

  Widget _label(String text, {bool optional = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      children: [
        Text(text, style: t(13, w: FontWeight.w600)),
        if (optional) ...[const SizedBox(width: 6), Text('Optional', style: t(12, c: C.muted))],
      ],
    ),
  );

  Widget _readOnly(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(label),
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: C.chip,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: C.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: t(15, c: C.mutedInk),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(LucideIcons.badgeCheck, size: 18, color: C.green700),
              const SizedBox(width: 4),
              Text(
                'Verified',
                style: t(12, w: FontWeight.w600, c: C.green700),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _field(
    TextEditingController c,
    String label,
    String hint,
    String? error, {
    bool optional = false,
    TextInputType type = TextInputType.text,
    TextCapitalization caps = TextCapitalization.none,
    String? prefix,
    String? help,
    String? autofill,
    int lines = 1,
    List<TextInputFormatter>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(label, optional: optional),
          Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: C.ground,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: error != null ? C.redInk : C.line),
            ),
            child: Row(
              children: [
                if (prefix != null) ...[Text(prefix, style: t(15, w: FontWeight.w600)), const SizedBox(width: 8)],
                Expanded(
                  child: TextField(
                    controller: c,
                    keyboardType: type,
                    textCapitalization: caps,
                    inputFormatters: formatters,
                    autofillHints: autofill == null ? null : [autofill],
                    minLines: 1,
                    maxLines: lines,
                    style: t(15),
                    onChanged: (_) {
                      if (error != null) context.read<ProfileFormCubit>().clearError(label == 'Full name' ? 'name' : 'phone');
                    },
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: hint,
                      hintStyle: t(15, c: C.muted),
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(error, style: t(12, c: C.redInk)),
            )
          else if (help != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(help, style: t(12, c: C.muted)),
            ),
        ],
      ),
    );
  }
}
