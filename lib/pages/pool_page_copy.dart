import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../control_plane/control_plane_controller.dart';
import '../../control_plane/control_plane_models.dart';
import '../../service_locator.dart';

class PoolPage extends StatefulWidget {
  const PoolPage({super.key});

  @override
  State<PoolPage> createState() => _PoolPageState();
}

class _PoolPageState extends State<PoolPage> {
  String? _selectedRegion;
  String? _selectedGpuTier;
  BillingUnit _selectedBillingUnit = BillingUnit.hour;
  int _rentCount = 1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshPool();
    });
  }

  Future<void> _refreshPool() async {
    setState(() => _isLoading = true);
    try {
      await getIt<ControlPlaneController>().refreshPool(
        region: _selectedRegion,
        gpuTier: _selectedGpuTier,
        status: NodeStatus.free,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rent() async {
    if (_selectedRegion == null || _selectedGpuTier == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择地域和规�?)),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await getIt<ControlPlaneController>().rent(
        region: _selectedRegion!,
        gpuTier: _selectedGpuTier!,
        billingUnit: _selectedBillingUnit,
        count: _rentCount,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('租赁成功！请前往“我的租赁”查�?)),
        );
        // Refresh pool to show updated availability
        _refreshPool();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('租赁失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('资源�?),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshPool,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(
            child: Consumer<ControlPlaneController>(
              builder: (context, controller, child) {
                if (_isLoading && controller.poolNodes.isEmpty) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (controller.poolNodes.isEmpty) {
                  return const Center(child: Text('暂无可用资源'));
                }

                // Group nodes by region and tier for display
                final groupedNodes = <String, List<PoolNode>>{};
                for (final node in controller.poolNodes) {
                  final key = '${node.region} - ${node.gpuTier}';
                  groupedNodes.putIfAbsent(key, () => []).add(node);
                }

                return ListView.builder(
                  itemCount: groupedNodes.length,
                  itemBuilder: (context, index) {
                    final key = groupedNodes.keys.elementAt(index);
                    final nodes = groupedNodes[key]!;
                    final firstNode = nodes.first;
                    final freeCount = nodes.where((n) => n.status == NodeStatus.free).length;

                    return Card(
                      margin: const EdgeInsets.all(8.0),
                      child: ListTile(
                        title: Text(key),
                        subtitle: Text('可用: $freeCount �?),
                        trailing: ElevatedButton(
                          onPressed: freeCount > 0 ? () {
                            setState(() {
                              _selectedRegion = firstNode.region;
                              _selectedGpuTier = firstNode.gpuTier;
                            });
                            _showRentDialog(context, freeCount);
                          } : null,
                          child: const Text('租用'),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedRegion,
              decoration: const InputDecoration(labelText: '地域'),
              items: const [
                DropdownMenuItem(value: null, child: Text('全部')),
                DropdownMenuItem(value: 'cn-shanghai', child: Text('上海')),
                DropdownMenuItem(value: 'cn-beijing', child: Text('北京')),
              ],
              onChanged: (value) {
                setState(() => _selectedRegion = value);
                _refreshPool();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedGpuTier,
              decoration: const InputDecoration(labelText: '规格'),
              items: const [
                DropdownMenuItem(value: null, child: Text('全部')),
                DropdownMenuItem(value: 'tier_1', child: Text('Tier 1')),
                DropdownMenuItem(value: 'tier_3', child: Text('Tier 3')),
                DropdownMenuItem(value: 'tier_5', child: Text('Tier 5')),
                DropdownMenuItem(value: 'tier_7', child: Text('Tier 7')),
              ],
              onChanged: (value) {
                setState(() => _selectedGpuTier = value);
                _refreshPool();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showRentDialog(BuildContext context, int maxCount) {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('租用配置'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<BillingUnit>(
                value: _selectedBillingUnit,
                decoration: const InputDecoration(labelText: '计费单位'),
                items: BillingUnit.values.map((e) {
                  return DropdownMenuItem(
                    value: e,
                    child: Text(e.name),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedBillingUnit = value);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('数量: '),
                  IconButton(
                    icon: const Icon(Icons.remove),
                    onPressed: _rentCount > 1 ? () => setState(() => _rentCount--) : null,
                  ),
                  Text('$_rentCount'),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _rentCount < maxCount ? () => setState(() => _rentCount++) : null,
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _rent();
              },
              child: const Text('确认租用'),
            ),
          ],
        ),
      ),
    );
  }
}
