import 'package:flutter/material.dart';
import 'package:glassmorphism_ui/glassmorphism_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ssh_service.dart';
import 'terminal_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _developerMode = false;
  final _commandController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final creds = await SshService.loadSavedCredentials();
    setState(() {
      _developerMode = creds['developerMode'] as bool? ?? false;
      _commandController.text = creds['customStartCommand'] as String? ?? '';
    });
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    await SshService.setDeveloperMode(_developerMode);
    await SshService.setCustomStartCommand(_commandController.text.trim());
    setState(() => _isSaving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('设置已保存', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.green.withOpacity(0.8),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _openTerminal() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TerminalScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '设置',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section: Developer Mode
            _buildSectionTitle('开发者选项', Icons.code),
            SizedBox(height: 12),
            GlassContainer(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              blur: 20,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Developer mode toggle
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '开发者模式',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '启用后可自定义启动命令、查看SSH终端输出',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _developerMode,
                          onChanged: (v) {
                            setState(() => _developerMode = v);
                          },
                          activeColor: Colors.cyanAccent,
                          activeTrackColor: Colors.cyanAccent.withOpacity(0.3),
                        ),
                      ],
                    ),

                    if (_developerMode) ...[
                      Divider(color: Colors.white.withOpacity(0.1), height: 24),
                      // Custom command editor
                      Text(
                        '自定义一键启动命令',
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '留空则使用默认命令：cd ~/rk3588_car_project/rk3588_backend && nohup bash start.sh > /tmp/car_backend.log 2>&1 &',
                        style: TextStyle(
                          color: Colors.grey.withOpacity(0.7),
                          fontSize: 11,
                        ),
                      ),
                      SizedBox(height: 10),
                      TextField(
                        controller: _commandController,
                        maxLines: 4,
                        style: TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          hintText: '输入自定义命令...',
                          hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5), fontSize: 12),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.cyanAccent.withOpacity(0.3)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.cyanAccent),
                          ),
                          contentPadding: EdgeInsets.all(12),
                        ),
                      ),

                      SizedBox(height: 16),
                      // Terminal button
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: SshService.isConnected ? _openTerminal : null,
                          icon: Icon(Icons.terminal, size: 18),
                          label: Text('查看 SSH 终端输出'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purpleAccent.withOpacity(0.2),
                            foregroundColor: Colors.purpleAccent,
                            disabledBackgroundColor: Colors.grey.withOpacity(0.1),
                            disabledForegroundColor: Colors.grey,
                            side: BorderSide(
                              color: SshService.isConnected
                                  ? Colors.purpleAccent.withOpacity(0.5)
                                  : Colors.grey.withOpacity(0.2),
                            ),
                            padding: EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      if (!SshService.isConnected)
                        Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            '需先建立 SSH 连接',
                            style: TextStyle(color: Colors.grey.withOpacity(0.5), fontSize: 11),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),
            // Section: Connection info
            _buildSectionTitle('连接信息', Icons.info_outline),
            SizedBox(height: 12),
            GlassContainer(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
              ),
              blur: 20,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoRow('SSH 主机', SshService.host.isEmpty ? '未连接' : SshService.host),
                    SizedBox(height: 8),
                    _buildInfoRow('SSH 端口', SshService.port.toString()),
                    SizedBox(height: 8),
                    _buildInfoRow('用户名', SshService.username.isEmpty ? '未连接' : SshService.username),
                    SizedBox(height: 8),
                    _buildInfoRow('连接状态', SshService.isConnected ? '已连接 ✅' : '未连接 ❌'),
                  ],
                ),
              ),
            ),

            SizedBox(height: 32),
            // Save button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveSettings,
                icon: _isSaving
                    ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Icon(Icons.save, size: 18),
                label: Text(_isSaving ? '保存中...' : '保存设置'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey.withOpacity(0.2),
                  padding: EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.cyanAccent, size: 18),
        SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            color: Colors.cyanAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        Spacer(),
        Text(
          value,
          style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
