import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Pairs short stock inputs on phones and stacks them for larger text.
class InventoryFieldPair extends StatelessWidget {
  const InventoryFieldPair(
      {required this.first, required this.second, super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 230 ||
              MediaQuery.textScalerOf(context).scale(13) > 17) {
            return Column(
                children: [first, const SizedBox(height: 10), second]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: first),
              const SizedBox(width: 12),
              Expanded(child: second),
            ],
          );
        },
      );
}

/// A shared presentation for stock forms. The caller owns form state and saves.
class InventoryFormShell extends StatelessWidget {
  const InventoryFormShell({
    required this.title,
    required this.child,
    required this.saveLabel,
    required this.saving,
    required this.onSave,
    this.onCancel,
    super.key,
  });

  final String title;
  final Widget child;
  final String saveLabel;
  final bool saving;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 600;
    final base = AppTheme.emeraldLight;
    final theme = base.copyWith(
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        isDense: true,
        fillColor: AppTheme.paper,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        labelStyle: const TextStyle(color: AppTheme.mutedInk, fontSize: 13),
        floatingLabelStyle:
            const TextStyle(color: AppTheme.emerald, fontSize: 13),
        hintStyle: const TextStyle(color: AppTheme.mutedInk, fontSize: 13),
      ),
    );

    return Theme(
      data: theme,
      child: Builder(builder: (context) {
        final cancel =
            saving ? null : onCancel ?? () => Navigator.of(context).pop();
        final content = LayoutBuilder(builder: (context, constraints) {
          const titleStyle = TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.2,
          );
          final titlePainter = TextPainter(
            text: TextSpan(text: title, style: titleStyle),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 3,
          )..layout(maxWidth: math.max(24.0, constraints.maxWidth - 152));
          final headerHeight = math.max(52.0, titlePainter.height + 20);
          titlePainter.dispose();

          return Scaffold(
            backgroundColor: AppTheme.forest,
            resizeToAvoidBottomInset: true,
            appBar: AppBar(
              toolbarHeight: headerHeight,
              backgroundColor: AppTheme.forest,
              foregroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              automaticallyImplyLeading: false,
              leading: IconButton(
                tooltip: 'Back',
                onPressed: cancel,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              titleSpacing: 0,
              title: Text(
                title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: titleStyle,
              ),
              actions: [
                TextButton(
                  onPressed: cancel,
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white,
                    disabledForegroundColor: Colors.white54,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(24)),
              child: ColoredBox(
                color: AppTheme.card,
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.all(16),
                        child: child,
                      ),
                    ),
                    SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: saving ? null : onSave,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.emerald,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(saveLabel, textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });

        if (compact) return Dialog.fullscreen(child: content);
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: SizedBox(
            width: 520,
            height: math.min(760.0, math.max(0.0, screen.height - 48)),
            child: content,
          ),
        );
      }),
    );
  }
}
