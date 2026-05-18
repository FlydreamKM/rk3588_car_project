import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/ssh_service.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({Key? key}) : super(key: key);

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();
  final _focusNode = FocusNode();
  List<String> _lines = [];
  bool _autoScroll = true;

  @override
  void initState() {
    super.initState();
    // Load existing history
    _lines = List<String>.from(SshService.outputHistory);
    // Listen to new output
    SshService.terminalOutput?.listen((data) {
      if (!mounted) return;
      setState(() {
        _lines = List<String>.from(SshService.outputHistory);
      });
      if (_autoScroll) {
        Future.delayed(Duration(milliseconds: 50), () {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _sendCommand() {
    final cmd = _inputController.text;
    if (cmd.isEmpty) return;
    SshService.writeToTerminal('$cmd\n');
    _inputController.clear();
    _focusNode.requestFocus();
  }

  void _sendCtrlC() {
    SshService.writeToTerminal('\x03');
  }

  void _clearScreen() {
    setState(() {
      _lines = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: Color(0xFF1A1A1A),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Icon(Icons.terminal, color: Colors.greenAccent, size: 18),
            SizedBox(width: 8),
            Text(
              'SSH 终端',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        actions: [
          // Auto-scroll toggle
          IconButton(
            icon: Icon(
              _autoScroll ? Icons.vertical_align_bottom : Icons.vertical_align_top,
              color: _autoScroll ? Colors.greenAccent : Colors.grey,
              size: 20,
            ),
            tooltip: _autoScroll ? '自动滚动已开启' : '自动滚动已关闭',
            onPressed: () {
              setState(() => _autoScroll = !_autoScroll);
            },
          ),
          // Ctrl+C
          TextButton(
            onPressed: _sendCtrlC,
            child: Text(
              'Ctrl+C',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ),
          // Clear
          IconButton(
            icon: Icon(Icons.clear_all, color: Colors.grey, size: 20),
            tooltip: '清屏',
            onPressed: _clearScreen,
          ),
          SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Connection status bar
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: SshService.isConnected ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: SshService.isConnected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  SshService.isConnected
                      ? '${SshService.username}@${SshService.host}:${SshService.port}'
                      : 'SSH 未连接',
                  style: TextStyle(
                    color: SshService.isConnected ? Colors.green : Colors.red,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

          // Terminal output
          Expanded(
            child: GestureDetector(
              onTap: () {
                // Tap terminal area to focus input
                _focusNode.requestFocus();
              },
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.all(12),
                  itemCount: _lines.length,
                  itemBuilder: (context, index) {
                    final line = _lines[index];
                    final isStderr = line.startsWith('[stderr]');
                    final displayLine = isStderr ? line.substring(8).trim() : line;
                    return SelectableText(
                      displayLine,
                      style: TextStyle(
                        color: isStderr ? Colors.redAccent : Colors.greenAccent,
                        fontSize: 12,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // Input area
          Container(
            color: Color(0xFF1A1A1A),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SafeArea(
              child: Row(
                children: [
                  Text(
                    '\$ ',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 14,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      focusNode: _focusNode,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                      decoration: InputDecoration(
                        hintText: SshService.isConnected ? '输入命令...' : 'SSH 未连接，无法输入',
                        hintStyle: TextStyle(color: Colors.grey.withOpacity(0.5), fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      enabled: SshService.isConnected,
                      onSubmitted: (_) => _sendCommand(),
                      textInputAction: TextInputAction.send,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send, color: Colors.cyanAccent, size: 20),
                    onPressed: SshService.isConnected ? _sendCommand : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
