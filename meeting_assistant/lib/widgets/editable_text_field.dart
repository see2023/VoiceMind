import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class EditableTextField extends StatefulWidget {
  final String initialText;
  final String? hintText;
  final TextStyle? textStyle;
  final InputDecoration? decoration;
  final Function(String) onSave;
  final VoidCallback? onCancel;
  final bool autofocus;

  const EditableTextField({
    super.key,
    required this.initialText,
    required this.onSave,
    this.onCancel,
    this.hintText,
    this.textStyle,
    this.decoration,
    this.autofocus = false,
  });

  @override
  State<EditableTextField> createState() => _EditableTextFieldState();
}

class _EditableTextFieldState extends State<EditableTextField> {
  late TextEditingController _textController;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
    if (widget.autofocus) {
      Future.delayed(const Duration(milliseconds: 50), () {
        _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSave() {
    widget.onSave(_textController.text);
  }

  void _handleNewLine() {
    final currentText = _textController.text;
    final selection = _textController.selection;
    final newText = currentText.replaceRange(
      selection.start,
      selection.end,
      '\n',
    );
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (_, KeyEvent event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            if (HardwareKeyboard.instance.isShiftPressed) {
              _handleNewLine();
              return KeyEventResult.handled;
            } else {
              _handleSave();
              return KeyEventResult.handled;
            }
          } else if (event.logicalKey == LogicalKeyboardKey.escape) {
            if (widget.onCancel != null) {
              widget.onCancel!();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: TextField(
        controller: _textController,
        maxLines: null,
        textInputAction: TextInputAction.done,
        keyboardType: TextInputType.multiline,
        onSubmitted: (_) => _handleSave(),
        style: widget.textStyle,
        decoration: (widget.decoration ??
                InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  border: InputBorder.none,
                  hintText: widget.hintText,
                ))
            .copyWith(
          hintText: widget.hintText,
          fillColor: Colors.grey[50],
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: Colors.grey[300]!,
              width: 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: Colors.grey[300]!,
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: BorderSide(
              color: Colors.blue[300]!,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
