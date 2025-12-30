part of 'admin_dashboard_bloc.dart';

abstract class AdminDashboardState extends Equatable {
  const AdminDashboardState();
  
  @override
  List<Object> get props => [];
}

class ClusterInitial extends AdminDashboardState {}

class ClusterLoading extends AdminDashboardState {}

class ClusterLoaded extends AdminDashboardState {
  final List<PoolNode> nodes;

  const ClusterLoaded(this.nodes);

  @override
  List<Object> get props => [nodes];
}

class ClusterError extends AdminDashboardState {
  final String message;

  const ClusterError(this.message);

  @override
  List<Object> get props => [message];
}
