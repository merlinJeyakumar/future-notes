import 'package:flutter/foundation.dart';
import '../models/counter_model.dart';

class CounterViewModel extends ChangeNotifier {
  CounterModel _state = const CounterModel(value: 0);

  CounterModel get state => _state;

  void incrementCounter() {
    _state = _state.copyWith(value: _state.value + 1);
    notifyListeners();
  }
}
