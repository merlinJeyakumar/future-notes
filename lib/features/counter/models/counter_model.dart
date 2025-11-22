import 'package:equatable/equatable.dart';

class CounterModel extends Equatable {
  final int value;

  const CounterModel({required this.value});

  CounterModel copyWith({int? value}) {
    return CounterModel(value: value ?? this.value);
  }

  @override
  List<Object?> get props => [value];
}
