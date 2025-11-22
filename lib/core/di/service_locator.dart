import 'package:get_it/get_it.dart';
import '../../features/counter/viewmodels/counter_viewmodel.dart';

final getIt = GetIt.instance;

void setupServiceLocator() {
  // ViewModels
  getIt.registerFactory(() => CounterViewModel());
}
