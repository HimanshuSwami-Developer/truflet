import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../bloc/data_cubit.dart';
import '../theme/theme.dart';
import 'buttons.dart';
import 'skeletons.dart';

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 2400)));
}

/// Bottom sheet chrome used across the app (handle + rounded top).
Future<T?> sheet<T>(BuildContext context, Widget Function(BuildContext) builder) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  barrierColor: const Color(0x7310231A),
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
  builder: (ctx) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(20, 12, 20, 32 + MediaQuery.of(ctx).viewInsets.bottom),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(color: C.dashed, borderRadius: BorderRadius.circular(999)),
          ),
        ),
        const SizedBox(height: 14),
        builder(ctx),
      ],
    ),
  ),
);

/// Skeleton → content, or an error with "Try again", for a [DataCubit] provided above this widget.
class DataBuilder<B extends DataCubit<T>, T> extends StatelessWidget {
  final Widget Function(BuildContext context, T data) builder;

  /// Shown while loading; shaped like the content.
  final Widget skeleton;
  const DataBuilder({super.key, required this.builder, this.skeleton = const ListSkeleton()});

  @override
  Widget build(BuildContext context) => BlocBuilder<B, DataState<T>>(
    builder: (context, s) {
      if (s.data != null) return builder(context, s.data as T);
      if (s.error != null) return ErrorRetry(s.error!, onRetry: context.read<B>().retry);
      return skeleton;
    },
  );
}

/// Loads a future and shows a skeleton / retry on error. Shorthand for a [DataCubit] + [DataBuilder].
class Loader<T> extends StatelessWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) builder;
  final Widget skeleton;
  const Loader({super.key, required this.load, required this.builder, this.skeleton = const ListSkeleton()});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => DataCubit<T>(load)..load(),
    child: DataBuilder<DataCubit<T>, T>(
      skeleton: skeleton,
      builder: (context, data) => builder(context, data, context.read<DataCubit<T>>().load),
    ),
  );
}

class ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const ErrorRetry(this.message, {super.key, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(LucideIcons.wifiOff, size: 36, color: C.muted),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: t(14, c: C.muted, h: 1.5),
          ),
          const SizedBox(height: 16),
          GhostButton('Try again', onTap: onRetry, height: 44),
        ],
      ),
    ),
  );
}
