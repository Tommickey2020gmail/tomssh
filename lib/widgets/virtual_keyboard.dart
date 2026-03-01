import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

/// A toolbar providing special keys not available on mobile soft keyboards.
/// Supports Ctrl/Alt/Shift as sticky modifiers and common terminal keys.
class VirtualKeyboard extends StatefulWidget {
  final Terminal terminal;
  const VirtualKeyboard({super.key, required this.terminal});

  @override
  State<VirtualKeyboard> createState() => _VirtualKeyboardState();
}

class _VirtualKeyboardState extends State<VirtualKeyboard> {
  bool _ctrl = false;
  bool _alt = false;
  bool _shift = false;
  bool _showFnKeys = false;

  void _sendKey(TerminalKey key) {
    widget.terminal.keyInput(key, ctrl: _ctrl, alt: _alt, shift: _shift);
    // Reset modifiers after sending a non-modifier key
    setState(() {
      _ctrl = false;
      _alt = false;
      _shift = false;
    });
  }

  void _sendChar(String char) {
    if (_ctrl || _alt) {
      // Map character to TerminalKey for modifier combos
      final keyMap = <String, TerminalKey>{
        'a': TerminalKey.keyA, 'b': TerminalKey.keyB, 'c': TerminalKey.keyC,
        'd': TerminalKey.keyD, 'e': TerminalKey.keyE, 'f': TerminalKey.keyF,
        'g': TerminalKey.keyG, 'h': TerminalKey.keyH, 'i': TerminalKey.keyI,
        'j': TerminalKey.keyJ, 'k': TerminalKey.keyK, 'l': TerminalKey.keyL,
        'm': TerminalKey.keyM, 'n': TerminalKey.keyN, 'o': TerminalKey.keyO,
        'p': TerminalKey.keyP, 'q': TerminalKey.keyQ, 'r': TerminalKey.keyR,
        's': TerminalKey.keyS, 't': TerminalKey.keyT, 'u': TerminalKey.keyU,
        'v': TerminalKey.keyV, 'w': TerminalKey.keyW, 'x': TerminalKey.keyX,
        'y': TerminalKey.keyY, 'z': TerminalKey.keyZ,
      };
      final tk = keyMap[char.toLowerCase()];
      if (tk != null) {
        _sendKey(tk);
        return;
      }
    }
    widget.terminal.textInput(char);
    setState(() {
      _ctrl = false;
      _alt = false;
      _shift = false;
    });
  }

  Widget _modifierButton(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: active ? Colors.green : Colors.grey[800],
          borderRadius: BorderRadius.circular(4),
          border: active ? Border.all(color: Colors.greenAccent, width: 1.5) : null,
        ),
        child: Text(label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white,
            fontSize: 13,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _keyButton(String label, {VoidCallback? onTap, double? width}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: Colors.grey[850],
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.grey[900],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Row 1: Modifiers + common keys
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                _modifierButton('Ctrl', _ctrl, () => setState(() => _ctrl = !_ctrl)),
                _modifierButton('Alt', _alt, () => setState(() => _alt = !_alt)),
                _modifierButton('Shift', _shift, () => setState(() => _shift = !_shift)),
                const SizedBox(width: 4),
                _keyButton('Esc', onTap: () => _sendKey(TerminalKey.escape)),
                _keyButton('Tab', onTap: () => _sendKey(TerminalKey.tab)),
                _keyButton('|', onTap: () => _sendChar('|')),
                _keyButton('~', onTap: () => _sendChar('~')),
                _keyButton('`', onTap: () => _sendChar('`')),
                _keyButton('/', onTap: () => _sendChar('/')),
                _keyButton('-', onTap: () => _sendChar('-')),
                _keyButton('_', onTap: () => _sendChar('_')),
                _keyButton('\\', onTap: () => _sendChar('\\')),
                _keyButton('{', onTap: () => _sendChar('{')),
                _keyButton('}', onTap: () => _sendChar('}')),
                _keyButton('[', onTap: () => _sendChar('[')),
                _keyButton(']', onTap: () => _sendChar(']')),
                _keyButton('\$', onTap: () => _sendChar('\$')),
                _keyButton('&', onTap: () => _sendChar('&')),
                _keyButton('=', onTap: () => _sendChar('=')),
                _keyButton(';', onTap: () => _sendChar(';')),
                _keyButton('"', onTap: () => _sendChar('"')),
                _keyButton("'", onTap: () => _sendChar("'")),
                _keyButton('Fn', onTap: () => setState(() => _showFnKeys = !_showFnKeys)),
              ],
            ),
          ),
          // Row 2: Arrow keys + navigation
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
            child: Row(
              children: [
                _keyButton('Home', onTap: () => _sendKey(TerminalKey.home)),
                _keyButton('End', onTap: () => _sendKey(TerminalKey.end)),
                _keyButton('PgUp', onTap: () => _sendKey(TerminalKey.pageUp)),
                _keyButton('PgDn', onTap: () => _sendKey(TerminalKey.pageDown)),
                _keyButton('Del', onTap: () => _sendKey(TerminalKey.delete)),
                _keyButton('Ins', onTap: () => _sendKey(TerminalKey.insert)),
                const SizedBox(width: 8),
                _keyButton('\u2190', onTap: () => _sendKey(TerminalKey.arrowLeft)),
                _keyButton('\u2193', onTap: () => _sendKey(TerminalKey.arrowDown)),
                _keyButton('\u2191', onTap: () => _sendKey(TerminalKey.arrowUp)),
                _keyButton('\u2192', onTap: () => _sendKey(TerminalKey.arrowRight)),
              ],
            ),
          ),
          // Row 3: F1-F12 (toggleable)
          if (_showFnKeys)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
              child: Row(
                children: List.generate(12, (i) {
                  final fKeys = [
                    TerminalKey.f1, TerminalKey.f2, TerminalKey.f3,
                    TerminalKey.f4, TerminalKey.f5, TerminalKey.f6,
                    TerminalKey.f7, TerminalKey.f8, TerminalKey.f9,
                    TerminalKey.f10, TerminalKey.f11, TerminalKey.f12,
                  ];
                  return _keyButton('F${i + 1}', onTap: () => _sendKey(fKeys[i]));
                }),
              ),
            ),
        ],
      ),
    );
  }
}
