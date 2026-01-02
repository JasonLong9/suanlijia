import 'package:flutter/material.dart';
import '../../models/gpu_server.dart';
import '../../control_plane/control_plane_controller.dart';
import '../../control_plane/control_plane_models.dart';
import '../../service_locator.dart';

/// 深色主题颜色常量
class ClusterColors {
  static const Color bgDark = Color(0xFF0D1B2A);
  static const Color cardDark = Color(0xFF1B2838);
  static const Color borderColor = Color(0xFF2D4A5E);
  static const Color textPrimary = Colors.white;
  static const Color textSecondary = Color(0xFF8899A6);
  
  static const Color statusAvailable = Color(0xFF4CAF50);  // 绿色
  static const Color statusInUse = Color(0xFF2196F3);      // 蓝色
  static const Color statusOffline = Color(0xFFF44336);    // 红色
}

class ClusterDashboardPage extends StatefulWidget {
  const ClusterDashboardPage({super.key});

  @override
  State<ClusterDashboardPage> createState() => _ClusterDashboardPageState();
}

class _ClusterDashboardPageState extends State<ClusterDashboardPage> {
  List<GpuServer> _servers = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  Future<void> _loadServers() async {
    setState(() => _isLoading = true);
    
    try {
      // 从 ControlPlaneController 获取真实的节点数据
      final controller = getIt<ControlPlaneController>();
      await controller.refreshPool(); // 刷新获取最新数据
      
      // 将 PoolNode 转换为 GpuServer
      final poolNodes = controller.poolNodes;
      _servers = poolNodes.map((node) => _poolNodeToGpuServer(node)).toList();
    } catch (e) {
      debugPrint('加载服务器列表失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 将后端 PoolNode 模型转换为前端 GpuServer 模型
  GpuServer _poolNodeToGpuServer(PoolNode node) {
    return GpuServer(
      id: node.deviceId,
      name: node.deviceId,  // 使用 deviceId 作为默认名称
      remark: node.agentVersion,  // 版本号作为备注
      location: (node.region == null || node.region == 'unknown') ? '石家庄' : node.region,
      gpuModel: 'RTX 4060',  // 默认使用 4060
      gpuTier: (node.gpuTier == null || node.gpuTier.isEmpty) ? '60系' : node.gpuTier,
      status: _mapNodeStatus(node.status),
      lastOnlineTime: node.lastSeen,
    );
  }

  /// 将后端 NodeStatus 映射到前端 ServerStatus
  ServerStatus _mapNodeStatus(NodeStatus status) {
    switch (status) {
      case NodeStatus.free:
        return ServerStatus.available;
      case NodeStatus.assigned:
      case NodeStatus.inUse:
        return ServerStatus.inUse;
      case NodeStatus.offline:
      case NodeStatus.disabled:
      case NodeStatus.maintenance:
      case NodeStatus.releasing:
      case NodeStatus.unknown:
        return ServerStatus.offline;
    }
  }

  int get _availableCount => 
      _servers.where((s) => s.status == ServerStatus.available).length;
  int get _inUseCount => 
      _servers.where((s) => s.status == ServerStatus.inUse).length;
  int get _offlineCount => 
      _servers.where((s) => s.status == ServerStatus.offline).length;

  Color _getStatusColor(ServerStatus status) {
    switch (status) {
      case ServerStatus.available:
        return ClusterColors.statusAvailable;
      case ServerStatus.inUse:
        return ClusterColors.statusInUse;
      case ServerStatus.offline:
        return ClusterColors.statusOffline;
    }
  }

  IconData _getStatusIcon(ServerStatus status) {
    switch (status) {
      case ServerStatus.available:
        return Icons.computer;
      case ServerStatus.inUse:
        return Icons.computer;
      case ServerStatus.offline:
        return Icons.computer_outlined;
    }
  }

  void _showServerConfigDialog(GpuServer server) {
    showDialog(
      context: context,
      builder: (context) => ServerConfigDialog(
        server: server,
        onSave: (updated) {
          setState(() {
            final index = _servers.indexWhere((s) => s.id == updated.id);
            if (index >= 0) {
              _servers[index] = updated;
            }
          });
        },
      ),
    );
  }

  Future<void> _restartServer(GpuServer server) async {
    if (!server.hasBmcConfig) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先配置 BMC 信息')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认重启'),
        content: Text('确定要通过 BMC 重启 ${server.name} 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('重启'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // TODO: 调用后端 API 执行 BMC 重启
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('正在重启 ${server.name}...')),
      );
    }
  }

  Future<void> _deleteServer(GpuServer server) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要彻底删除服务器 ${server.name} 吗？\n\n此操作不可恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: ClusterColors.statusOffline,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await getIt<ControlPlaneController>().deleteNode(server.id);
        if (mounted) {
          setState(() {
            _servers.removeWhere((s) => s.id == server.id);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('服务器 ${server.name} 已成功删除')),
          );
        }
      } catch (e) {
        if (mounted) {
          String errorMessage = e.toString();
          if (e is ControlPlaneApiException) {
            errorMessage = e.message;
            if (e.code == 'RAW_RESPONSE' && e.details != null) {
              errorMessage = '${e.message}\n${e.details}';
            }
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('删除失败: $errorMessage'),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ClusterColors.bgDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildStatusBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadServers,
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildServerGrid(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.dns, color: ClusterColors.textPrimary, size: 28),
          const SizedBox(width: 12),
          const Text(
            '算力集群管理',
            style: TextStyle(
              color: ClusterColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, color: ClusterColors.textPrimary),
            onPressed: _loadServers,
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ClusterColors.cardDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ClusterColors.borderColor),
      ),
      child: Row(
        children: [
          _buildStatusChip(
            '可用',
            _availableCount,
            ClusterColors.statusAvailable,
          ),
          const SizedBox(width: 24),
          _buildStatusChip(
            '使用中',
            _inUseCount,
            ClusterColors.statusInUse,
          ),
          const SizedBox(width: 24),
          _buildStatusChip(
            '离线',
            _offlineCount,
            ClusterColors.statusOffline,
          ),
          const Spacer(),
          Text(
            '共 ${_servers.length} 台',
            style: const TextStyle(
              color: ClusterColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, int count, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count $label',
          style: const TextStyle(
            color: ClusterColors.textPrimary,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildServerGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: _servers.length,
      itemBuilder: (context, index) {
        return _buildServerCard(_servers[index]);
      },
    );
  }

  Widget _buildServerCard(GpuServer server) {
    final statusColor = _getStatusColor(server.status);
    
    return Container(
      decoration: BoxDecoration(
        color: ClusterColors.cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ClusterColors.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 状态图标
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Row(
              children: [
                Icon(
                  _getStatusIcon(server.status),
                  color: statusColor,
                  size: 32,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(40),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    server.statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 服务器名称
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Text(
              server.name,
              style: const TextStyle(
                color: ClusterColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          
          // 备注
          if (server.remark != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Text(
                server.remark!,
                style: const TextStyle(
                  color: ClusterColors.textSecondary,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          
          // 位置 + 显卡
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Text(
              '${server.location ?? '-'} · ${server.gpuModel ?? '-'}',
              style: const TextStyle(
                color: ClusterColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          
          // 使用中显示用户
          if (server.status == ServerStatus.inUse && server.currentUserName != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: Text(
                '用户: ${server.currentUserName}',
                style: const TextStyle(
                  color: ClusterColors.statusInUse,
                  fontSize: 11,
                ),
              ),
            ),
          
          const Spacer(),
          
          // 操作按钮
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    // 配置按钮
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _showServerConfigDialog(server),
                        icon: const Icon(Icons.settings, size: 18),
                        label: const Text('配置'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blueAccent,
                          side: const BorderSide(color: Colors.blueAccent),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 重启按钮
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: server.status == ServerStatus.offline
                            ? () => _restartServer(server)
                            : null,
                        icon: const Icon(Icons.restart_alt, size: 18),
                        label: const Text('重启'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orangeAccent,
                          side: server.status == ServerStatus.offline 
                              ? const BorderSide(color: Colors.orangeAccent)
                              : null,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (server.status == ServerStatus.offline) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteServer(server),
                      icon: const Icon(Icons.delete_forever, size: 18),
                      label: const Text('删除服务器'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 服务器配置对话框
class ServerConfigDialog extends StatefulWidget {
  final GpuServer server;
  final Function(GpuServer) onSave;

  const ServerConfigDialog({
    super.key,
    required this.server,
    required this.onSave,
  });

  @override
  State<ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<ServerConfigDialog> {
  late TextEditingController _remarkController;
  late TextEditingController _bmcAddressController;
  late TextEditingController _bmcUsernameController;
  late TextEditingController _bmcPasswordController;
  String? _selectedLocation;
  String? _selectedGpuModel;
  String? _selectedGpuTier;

  @override
  void initState() {
    super.initState();
    _remarkController = TextEditingController(text: widget.server.remark);
    _bmcAddressController = TextEditingController(text: widget.server.bmcAddress);
    _bmcUsernameController = TextEditingController(text: widget.server.bmcUsername);
    _bmcPasswordController = TextEditingController(text: widget.server.bmcPassword);
    _selectedLocation = widget.server.location;
    _selectedGpuModel = widget.server.gpuModel;
    _selectedGpuTier = widget.server.gpuTier;
  }

  @override
  void dispose() {
    _remarkController.dispose();
    _bmcAddressController.dispose();
    _bmcUsernameController.dispose();
    _bmcPasswordController.dispose();
    super.dispose();
  }

  void _save() {
    final updated = GpuServer(
      id: widget.server.id,
      name: widget.server.name,
      remark: _remarkController.text.isEmpty ? null : _remarkController.text,
      location: _selectedLocation,
      gpuModel: _selectedGpuModel,
      gpuTier: _selectedGpuTier,
      status: widget.server.status,
      lastOnlineTime: widget.server.lastOnlineTime,
      bmcAddress: _bmcAddressController.text.isEmpty ? null : _bmcAddressController.text,
      bmcUsername: _bmcUsernameController.text.isEmpty ? null : _bmcUsernameController.text,
      bmcPassword: _bmcPasswordController.text.isEmpty ? null : _bmcPasswordController.text,
      currentLeaseId: widget.server.currentLeaseId,
      currentUserId: widget.server.currentUserId,
      currentUserName: widget.server.currentUserName,
    );
    widget.onSave(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('配置 ${widget.server.name}'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 备注
              TextField(
                controller: _remarkController,
                decoration: const InputDecoration(
                  labelText: '备注',
                  hintText: '输入备注信息',
                ),
              ),
              const SizedBox(height: 16),
              
              // 地理位置
              DropdownButtonFormField<String>(
                value: _selectedLocation,
                decoration: const InputDecoration(labelText: '地理位置'),
                items: predefinedLocations.map((loc) {
                  return DropdownMenuItem(value: loc, child: Text(loc));
                }).toList(),
                onChanged: (v) => setState(() => _selectedLocation = v),
              ),
              const SizedBox(height: 16),
              
              // 显卡型号
              DropdownButtonFormField<String>(
                value: _selectedGpuModel,
                decoration: const InputDecoration(labelText: '显卡型号'),
                items: predefinedGpuModels.map((gpu) {
                  return DropdownMenuItem(value: gpu, child: Text(gpu));
                }).toList(),
                onChanged: (v) => setState(() => _selectedGpuModel = v),
              ),
              const SizedBox(height: 16),
              
              // 显卡池分类
              DropdownButtonFormField<String>(
                value: _selectedGpuTier,
                decoration: const InputDecoration(labelText: '显卡池分类'),
                items: predefinedGpuTiers.map((tier) {
                  return DropdownMenuItem(value: tier, child: Text(tier));
                }).toList(),
                onChanged: (v) => setState(() => _selectedGpuTier = v),
              ),
              
              const Divider(height: 32),
              
              const Text(
                'BMC 远程管理配置',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              
              // BMC 地址
              TextField(
                controller: _bmcAddressController,
                decoration: const InputDecoration(
                  labelText: 'BMC 地址',
                  hintText: '如: 192.168.1.100',
                ),
              ),
              const SizedBox(height: 12),
              
              // BMC 用户名
              TextField(
                controller: _bmcUsernameController,
                decoration: const InputDecoration(
                  labelText: 'BMC 用户名',
                  hintText: '如: admin',
                ),
              ),
              const SizedBox(height: 12),
              
              // BMC 密码
              TextField(
                controller: _bmcPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'BMC 密码',
                  hintText: '输入密码',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
