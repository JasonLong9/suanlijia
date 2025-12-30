import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../control_plane/control_plane_controller.dart';
import '../../control_plane/control_plane_models.dart';
import '../../service_locator.dart';

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      getIt<ControlPlaneController>().refreshBilling();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('账单'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => getIt<ControlPlaneController>().refreshBilling(),
          ),
        ],
      ),
      body: Consumer<ControlPlaneController>(
        builder: (context, controller, child) {
          final info = controller.billingInfo;
          if (info == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              _buildBalanceCard(info),
              const Divider(),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('历史账单', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: info.history.length,
                  itemBuilder: (context, index) {
                    final record = info.history[index];
                    return ListTile(
                      leading: const Icon(Icons.receipt_long),
                      title: Text('Lease: ${record.leaseId}'),
                      subtitle: Text('${record.createdAt.toLocal()}'),
                      trailing: Text(
                        '-${record.amount.toStringAsFixed(2)} ${info.currency}',
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildBalanceCard(BillingInfo info) {
    return Card(
      margin: const EdgeInsets.all(16.0),
      color: Theme.of(context).primaryColor,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text('当前余额', style: TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              '${info.balance.toStringAsFixed(2)} ${info.currency}',
              style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
