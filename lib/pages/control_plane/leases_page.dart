import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../control_plane/control_plane_controller.dart';
import '../../control_plane/control_plane_models.dart';
import '../../service_locator.dart';
import 'lease_remote_control_page.dart';

class LeasesPage extends StatefulWidget {
  const LeasesPage({super.key});

  @override
  State<LeasesPage> createState() => _LeasesPageState();
}

class _LeasesPageState extends State<LeasesPage> {
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshLeases());
  }

  Future<void> _refreshLeases() async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await getIt<ControlPlaneController>().refreshLeases();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _releaseLease(Lease lease) async {
    try {
      await getIt<ControlPlaneController>().release(leaseIds: [lease.leaseId]);
      await getIt<ControlPlaneController>().refreshLeases();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已释放')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('释放失败: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的租赁'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: _refreshLeases,
          ),
        ],
      ),
      body: Consumer<ControlPlaneController>(
        builder: (context, controller, child) {
          final leases = controller.leasesById.values.toList()
            ..sort((a, b) => (b.startedAt ?? DateTime.now())
                .compareTo(a.startedAt ?? DateTime.now()));

          if (leases.isEmpty) {
            if (_isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (_error != null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('加载失败: $_error'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _refreshLeases,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              );
            }
            return const Center(child: Text('暂无租赁记录'));
          }

          return RefreshIndicator(
            onRefresh: _refreshLeases,
            child: ListView.builder(
              itemCount: leases.length,
              itemBuilder: (context, index) {
                final lease = leases[index];
                return Card(
                  margin: const EdgeInsets.all(8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Lease ID: ${lease.leaseId}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            _buildStatusChip(lease.status),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('设备 ID: ${lease.deviceId}'),
                        Text('计费模式: ${lease.billingUnit.name}'),
                        if (lease.startedAt != null)
                          Text('开始时间: ${lease.startedAt!.toLocal()}'),
                        if (lease.endedAt != null)
                          Text('结束时间: ${lease.endedAt!.toLocal()}'),
                        if (lease.endReason != null)
                          Text(
                            '结束原因: ${lease.endReason!.name}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (lease.status == LeaseStatus.ready ||
                                lease.status == LeaseStatus.active) ...[
                              ElevatedButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => LeaseRemoteControlPage(
                                        lease: lease,
                                      ),
                                    ),
                                  );
                                },
                                child: const Text('进入远控'),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () => _confirmRelease(lease),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red,
                                ),
                                child: const Text('释放资源'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusChip(LeaseStatus status) {
    Color color;
    switch (status) {
      case LeaseStatus.active:
      case LeaseStatus.ready:
        color = Colors.green;
        break;
      case LeaseStatus.pending:
      case LeaseStatus.assigned:
        color = Colors.orange;
        break;
      case LeaseStatus.ended:
        color = Colors.grey;
        break;
      default:
        color = Colors.blue;
    }
    return Chip(
      label: Text(
        status.name.toUpperCase(),
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color,
    );
  }

  void _confirmRelease(Lease lease) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认释放'),
        content: const Text('释放后将立即停止计费，设备将重启。确定要释放吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              await _releaseLease(lease);
            },
            child: const Text('确认释放'),
          ),
        ],
      ),
    );
  }
}
