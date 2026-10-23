import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import '../theme/app_theme.dart';
import 'tile.dart';

class TodoPanel extends StatefulWidget {
  const TodoPanel({super.key, required this.scope});

  final TodoScope scope;

  @override
  State<TodoPanel> createState() => _TodoPanelState();
}

class _TodoPanelState extends State<TodoPanel> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(AppState state) {
    if (_controller.text.trim().isEmpty) return;
    state.addTodo(widget.scope, _controller.text);
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final items = state.todos[widget.scope]!;
    final open = items.where((t) => !t.done).length;

    return Tile(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TileHeader(
              title: widget.scope.label,
              caption: open == 0 && items.isNotEmpty ? 'All clear' : '$open open',
            ),
          ),
          const SizedBox(height: 10),
          // Fills the card; scrolls only if the list outgrows it.
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: p.empty.withValues(alpha: 0.6),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.wb_sunny_outlined,
                                size: 16,
                                color: p.inkMuted.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'All clear',
                              style: TextStyle(
                                fontFamily: Fonts.body,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: p.inkMuted.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView(
                    padding: EdgeInsets.zero,
                    children: [for (final item in items) _TodoRow(scope: widget.scope, item: item)],
                  ),
          ),
          Container(
            margin: const EdgeInsets.only(top: 6, right: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
            decoration: BoxDecoration(
              color: p.empty.withValues(alpha: _focus.hasFocus ? 0.65 : 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focus.hasFocus ? p.accent.withValues(alpha: 0.45) : Colors.transparent,
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 18,
                  color: _focus.hasFocus ? p.accent : p.inkMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    style: TextStyle(fontFamily: Fonts.body, fontSize: 13.5, color: p.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Add a task',
                      hintStyle: TextStyle(
                        fontFamily: Fonts.body,
                        color: p.inkMuted.withValues(alpha: 0.65),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 9),
                    ),
                    onSubmitted: (_) => _submit(state),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodoRow extends StatefulWidget {
  const _TodoRow({required this.scope, required this.item});

  final TodoScope scope;
  final TodoItem item;

  @override
  State<_TodoRow> createState() => _TodoRowState();
}

class _TodoRowState extends State<_TodoRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final state = AppScope.of(context);
    final item = widget.item;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => state.toggleTodo(item),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: _hover ? p.empty.withValues(alpha: 0.35) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _Check(done: item.done),
              const SizedBox(width: 11),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontFamily: Fonts.body,
                    fontSize: 14,
                    height: 1.35,
                    color: item.done
                        ? p.inkMuted.withValues(alpha: p.brightness == Brightness.dark ? 0.75 : 0.7)
                        : p.ink,
                    decoration: item.done ? TextDecoration.lineThrough : null,
                    decorationColor: p.inkMuted.withValues(alpha: 0.45),
                  ),
                  child: Text(item.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
              ),
              if (item.carried > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: p.missed.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, size: 11, color: p.missed),
                      const SizedBox(width: 3),
                      Text(
                        'carried ×${item.carried}',
                        style: TextStyle(
                          fontFamily: Fonts.ui,
                          fontSize: 10.5,
                          color: p.missed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: const Duration(milliseconds: 150),
                child: Tooltip(
                  message: 'Remove',
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _hover ? () => state.removeTodo(widget.scope, item) : null,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.empty.withValues(alpha: 0.8),
                        ),
                        child: Icon(Icons.close_rounded, size: 14, color: p.inkMuted),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return RepaintBoundary(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: done ? LinearGradient(colors: [p.done, p.other]) : null,
          border: done
              ? null
              : Border.all(color: p.inkMuted.withValues(alpha: 0.38), width: 1.5),
          boxShadow: done
              ? [
                  BoxShadow(
                    color: p.done.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: done
            ? Icon(Icons.check_rounded, size: 13, color: p.onAccent)
            : null,
      ),
    );
  }
}
