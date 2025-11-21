import 'src/base_box_manager.dart';
import 'src/typedefs.dart';

export 'src/dual/base_dual_index_managers.dart';
export 'src/models.dart';
export 'src/simple/simple_box_managers.dart';
export 'src/single/single_index_box_manager.dart';
export 'src/single/single_index_lazy_box_manager.dart';

void assignManagerLogCallback(LogCallback? logCallback) =>
    BaseBoxManager.assignCallback(logCallback);
