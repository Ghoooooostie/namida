import 'package:flutter/material.dart';
import 'package:nampack/nampack.dart';

import 'package:namida/controller/navigator_controller.dart';
import 'package:namida/core/extensions.dart';
import 'package:namida/core/icon_fonts/broken_icons.dart';
import 'package:namida/core/utils.dart';
import 'package:namida/ui/dialogs/edit_tags_dialog.dart' show CustomTagTextField;
import 'package:namida/ui/widgets/custom_widgets.dart';

/// Shell for the AI subtitle pages.
///
/// It renders **content only**, exactly like a `SettingSubpageProvider` does:
/// when hosted by `SettingsSubPage` (the settings list pushes every subpage
/// through it) the wallpaper, the gradient and the scroll view are already
/// provided, and this widget is placed inside a `Column(mainAxisSize: min)`.
///
/// Two things must therefore never appear here: a [Scaffold]/[AppBar] (the
/// route already has one, a second one breaks the layout) and anything with an
/// unbounded height ([ListView], [Expanded], `SizedBox.expand`) — the host gives
/// unbounded height, so those either throw or silently render nothing, which is
/// what a blank page looks like.
///
/// Set [standalone] for the pages that are pushed directly with
/// `NamidaNavigator.inst.navigateToRoot` (from the track menu) and therefore
/// miss that host.
class AiSubtitlePage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Widget> children;
  final List<Widget>? actions;

  /// provides its own background & scroll view, for pushes outside the settings host.
  final bool standalone;

  const AiSubtitlePage({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.subtitle,
    this.actions,
    this.standalone = false,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4.0, 8.0, 4.0, 8.0),
          child: Row(
            children: [
              Icon(icon, size: 22.0, color: context.theme.colorScheme.primary),
              const SizedBox(width: 10.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: context.textTheme.titleMedium),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: context.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (actions != null) ...actions!,
            ],
          ),
        ),
        ...children,
        // -- clears the miniplayer
        const SizedBox(height: 90.0),
      ],
    );

    if (!standalone) return content;

    return BackgroundWrapper(
      child: Stack(
        children: [
          Container(height: context.height, color: context.theme.scaffoldBackgroundColor),
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: content,
          ),
        ],
      ),
    );
  }
}

/// A row of selectable pills.
///
/// Styled exactly like the smart playlist dialog's `_ChoiceChipsWrap` (pill
/// radius, `secondaryContainer` fill) so the AI subtitle pages look like the
/// rest of the app, and built on [NamidaInkWellButton] rather than a hand
/// rolled ink well, so the tap handling is the proven one.
class AiSubtitlePills<T> extends StatelessWidget {
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final String? Function(T value)? descriptionOf;
  final void Function(T value) onSelected;
  final bool Function(T value)? enabledOf;

  const AiSubtitlePills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
    this.descriptionOf,
    this.enabledOf,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.theme.colorScheme;
    final description = descriptionOf?.call(selected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 4.0,
          runSpacing: 4.0,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            for (final value in values)
              Builder(builder: (context) {
                final isSelected = value == selected;
                final isEnabled = enabledOf?.call(value) ?? true;

                // -- the selected state has to be obvious: a small alpha
                // -- difference between two shades of the same color reads as
                // -- "nothing happened" when you tap a pill.
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0),
                  child: NamidaInkWellButton(
                    icon: null,
                    borderRadius: 99.0,
                    text: labelOf(value),
                    enabled: isEnabled,
                    bgColor: isSelected ? colorScheme.secondaryContainer : Colors.transparent,
                    trailing: Icon(
                      Broken.tick_circle,
                      size: 15.0,
                      color: isSelected ? colorScheme.onSecondaryContainer : Colors.transparent,
                    ).animateEntrance(
                      showWhen: isSelected,
                      allCurves: Curves.fastLinearToSlowEaseIn,
                      durationMS: 200,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(99.0),
                      border: Border.all(
                        color: isSelected ? colorScheme.secondaryContainer : colorScheme.outlineVariant,
                        width: 1.2,
                      ),
                    ),
                    onTap: () => onSelected(value),
                  ),
                );
              }),
          ],
        ),
        if (description != null && description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10.0),
            child: Text(description, style: context.textTheme.bodySmall),
          ),
      ],
    );
  }
}

/// Opens a dialog with one field, [onSubmit] gets whatever the user typed.
Future<void> showAiSubtitleTextDialog({
  required String title,
  required String label,
  String? hintText,
  String? subtitle,
  String initialValue = '',
  bool obscure = false,
  int maxLines = 1,
  String submitText = 'Save',
  required void Function(String value) onSubmit,
}) async {
  final controller = TextEditingController(text: initialValue);

  await NamidaNavigator.inst.navigateDialog(
    dialog: CustomBlurryDialog(
      title: title,
      normalTitleStyle: true,
      actions: [
        const CancelButton(),
        NamidaButton(
          text: submitText,
          onTap: () {
            onSubmit(controller.text.trim());
            NamidaNavigator.inst.closeDialog();
          },
        ),
      ],
      child: Builder(
        builder: (context) => Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (subtitle != null) ...[
                Text(subtitle, style: context.textTheme.bodySmall),
                const SizedBox(height: 12.0),
              ],
              CustomTagTextField(
                controller: controller,
                labelText: label,
                hintText: hintText ?? '',
                obscureText: obscure,
                maxLines: obscure ? 1 : maxLines,
              ),
            ],
          ),
        ),
      ),
    ),
  );

  controller.dispose();
}
