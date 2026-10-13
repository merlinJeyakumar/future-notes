import 'owned_app_services.dart';
import 'storage_environment.dart';

typedef ValidationOwnerStarter = StorageOwnerStarter;

/// The validation entry point remains unable to admit native preview paths.
class ValidationAppServices extends OwnedAppServices {
  ValidationAppServices({
    required StorageEnvironment environment,
    ValidationOwnerStarter? startOwner,
  }) : super(environment: _isolated(environment), startOwner: startOwner);

  static StorageEnvironment _isolated(StorageEnvironment environment) {
    if (!environment.isValidation) {
      throw ArgumentError('Application validation requires isolated storage.');
    }
    return environment;
  }
}
