import 'package:mevora/core/identity/auth_uid_source.dart';
import 'package:mevora/core/network/backend_callable.dart';
import 'package:mevora/core/network/firebase_functions_callable.dart';
import 'package:mevora/core/services/app_logger.dart';
import 'package:mevora/features/boost/data/datasources/firebase_purchase_data_source.dart';
import 'package:mevora/features/boost/data/datasources/in_app_store_purchase_data_source.dart';
import 'package:mevora/features/boost/data/datasources/store_purchase_data_source.dart';
import 'package:mevora/features/boost/data/repositories/purchase_repository_impl.dart';
import 'package:mevora/features/boost/data/services/apple_purchase_service.dart';
import 'package:mevora/features/boost/data/services/google_purchase_service.dart';
import 'package:mevora/features/boost/domain/config/boost_product_config.dart';
import 'package:mevora/features/boost/domain/repositories/purchase_repository.dart';

class BoostServices {
  const BoostServices({required this.purchaseRepository});

  final PurchaseRepository purchaseRepository;
}

BoostServices createBoostServices({
  required AuthUidSource uidSource,
  BackendCallable? backend,
  StorePurchaseDataSource? store,
  AppLogger? logger,
  BoostProductConfig config = const BoostProductConfig(),
}) {
  final resolvedStore =
      store ??
      InAppStorePurchaseDataSource(
        apple: ApplePurchaseService(logger: logger),
        google: GooglePurchaseService(logger: logger),
        logger: logger,
      );
  return BoostServices(
    purchaseRepository: PurchaseRepositoryImpl(
      store: resolvedStore,
      remote: FirebasePurchaseDataSource(
        backend: backend ?? FirebaseFunctionsCallable(),
        logger: logger,
      ),
      uidSource: uidSource,
      config: config,
    ),
  );
}
