import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import '../../control_plane/control_plane_models.dart';
import '../../services/admin_service.dart';

part 'admin_dashboard_event.dart';
part 'admin_dashboard_state.dart';

class AdminDashboardBloc extends Bloc<AdminDashboardEvent, AdminDashboardState> {
  final AdminService _adminService;

  AdminDashboardBloc(this._adminService) : super(ClusterInitial()) {
    on<LoadClusterStatus>(_onLoadClusterStatus);
  }

  Future<void> _onLoadClusterStatus(
    LoadClusterStatus event,
    Emitter<AdminDashboardState> emit,
  ) async {
    emit(ClusterLoading());
    try {
      final nodes = await _adminService.fetchNodes();
      emit(ClusterLoaded(nodes));
    } catch (e) {
      emit(ClusterError(e.toString()));
    }
  }
}
