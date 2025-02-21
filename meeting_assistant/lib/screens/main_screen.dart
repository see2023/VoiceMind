import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controllers/recording_controller.dart';
import 'control_panel.dart';
import 'conversation_panel.dart';
import 'analysis_panel.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  double controlPanelWidth = 250;
  double dividerWidth = 8;
  double conversationRatio = 0.55;

  final GlobalKey _rowKey = GlobalKey();

  Widget _buildDivider({required Function(DragUpdateDetails) onDrag}) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: onDrag,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Container(
            width: dividerWidth,
            color: Colors.grey[300],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Get.put(RecordingController());

    return Scaffold(
      body: Row(
        key: _rowKey,
        children: [
          SizedBox(
            width: controlPanelWidth,
            child: const ControlPanel(),
          ),
          _buildDivider(
            onDrag: (details) {
              setState(() {
                controlPanelWidth += details.delta.dx;
                controlPanelWidth = controlPanelWidth.clamp(150.0, 400.0);
              });
            },
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final availableWidth = constraints.maxWidth;
                return Row(
                  children: [
                    SizedBox(
                      width: availableWidth * conversationRatio,
                      child: const ConversationPanel(),
                    ),
                    _buildDivider(
                      onDrag: (details) {
                        setState(() {
                          final delta = details.delta.dx / availableWidth;
                          conversationRatio =
                              (conversationRatio + delta).clamp(0.2, 0.8);
                        });
                      },
                    ),
                    const Expanded(
                      child: AnalysisPanel(),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
