import 'package:flutter_bloc/flutter_bloc.dart';

/// Loading / loaded / failed for a single request. Used by the generic [Loader] widget.
class DataState<T> {
  final T? data;
  final String? error;
  const DataState({this.data, this.error});
}

class DataCubit<T> extends Cubit<DataState<T>> {
  final Future<T> Function() _fetch;
  DataCubit(this._fetch) : super(DataState<T>());

  Future<void> load() async {
    try {
      final r = await _fetch();
      if (!isClosed) emit(DataState<T>(data: r));
    } catch (e) {
      if (!isClosed) emit(DataState<T>(data: state.data, error: e.toString()));
    }
  }

  /// Clears the error (back to the spinner) and loads again.
  void retry() {
    if (isClosed) return;
    emit(DataState<T>(data: state.data));
    load();
  }
}
