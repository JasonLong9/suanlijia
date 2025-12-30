import 'package:slc/blocs/admin_dashboard/admin_dashboard_bloc.dart';
import 'package:slc/blocs/device_control/device_control_bloc.dart';
import 'package:slc/control_plane/control_plane_models.dart';
import 'package:slc/services/admin_service.dart';
import 'package:slc/service_locator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (context) => AdminDashboardBloc(getIt<AdminService>())
            ..add(LoadClusterStatus()),
        ),
        BlocProvider(
          create: (context) => DeviceControlBloc(getIt<AdminService>()),
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('超级管理员仪表盘'),
          actions: [
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  context.read<AdminDashboardBloc>().add(LoadClusterStatus());
                },
              ),
            ),
          ],
        ),
        body: const AdminDashboardView(),
      ),
    );
  }
}

class AdminDashboardView extends StatelessWidget {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocListener<DeviceControlBloc, DeviceControlState>(
      listener: (context, state) {
        if (state is DeviceControlSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.green),
          );
          context.read<AdminDashboardBloc>().add(LoadClusterStatus());
        } else if (state is DeviceControlFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red),
          );
        }
      },
      child: BlocBuilder<AdminDashboardBloc, AdminDashboardState>(
        builder: (context, state) {
          if (state is ClusterLoading) {
            return const Center(child: CircularProgressIndicator());
          } else if (state is ClusterError) {
            return Center(child: Text('Error: ${state.message}'));
          } else if (state is ClusterLoaded) {
            return RefreshIndicator(
              onRefresh: () async {
                context.read<AdminDashboardBloc>().add(LoadClusterStatus());
              },
              child: ListView.builder(
                itemCount: state.nodes.length,
                itemBuilder: (context, index) {
                  final node = state.nodes[index];
                  final isOnline = node.status != NodeStatus.offline;
                  return Card(
                    margin: const EdgeInsets.all(8.0),
                    child: ListTile(
                      leading: Icon(
                        Icons.computer,
                        color: isOnline ? Colors.green : Colors.grey,
                      ),
                      title: Text('${node.deviceId} (${node.region}/${node.gpuTier})'),
                      subtitle: Text(
                        '状�? ${node.status.name.toUpperCase()} | lastSeen: ${node.lastSeen.toLocal()}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.restart_alt),
                            tooltip: '重启',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('确认重启'),
                                  content: Text('确定要重启节�?${node.deviceId} 吗？'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        context
                                            .read<DeviceControlBloc>()
                                            .add(RebootDevice(node.deviceId));
                                      },
                                      child: const Text('确定'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_forever),
                            tooltip: '强制释放',
                            onPressed: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('确认释放'),
                                  content: Text('确定要强制释放节�?${node.deviceId} 吗？'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('取消'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        context
                                            .read<DeviceControlBloc>()
                                            .add(ReleaseDevice(node.deviceId));
                                      },
                                      child: const Text('确定', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          }
          return const Center(child: Text('No data'));
        },
      ),
    );
  }
}
