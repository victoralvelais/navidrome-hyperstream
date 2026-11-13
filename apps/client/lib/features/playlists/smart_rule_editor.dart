import '../../widgets/glass_overlays.dart';

import 'package:flutter/material.dart';

import '../../widgets/floating_chrome.dart';
import '../../widgets/edge_back_gesture.dart';
import '../../models/smart_playlist.dart';

class SmartRuleEditor extends StatelessWidget {
  const SmartRuleEditor({
    super.key,
    required this.title,
    required this.group,
    required this.onChanged,
    this.depth = 0,
  });
  final String title;
  final SmartGroup group;
  final ValueChanged<SmartGroup> onChanged;
  final int depth;

  void _replace(int index, SmartRule? rule) {
    final children = [...group.children];
    if (rule == null) {
      children.removeAt(index);
    } else {
      children[index] = rule;
    }
    onChanged(SmartGroup(all: group.all, children: children));
  }

  Future<void> _condition(BuildContext context, [int? index]) async {
    final value = await showDialog<SmartCondition>(
      context: context,
      builder: (_) => _ConditionDialog(
        initial: index == null
            ? const SmartCondition(SmartField.added, SmartOperator.within, '30')
            : group.children[index] as SmartCondition,
      ),
    );
    if (value == null) return;
    if (index != null) {
      _replace(index, value);
    } else {
      onChanged(
        SmartGroup(all: group.all, children: [...group.children, value]),
      );
    }
  }

  Future<void> _group(BuildContext context, [int? index]) async {
    final value = await Navigator.of(context).push<SmartGroup>(
      MenuPageRoute(
        builder: (_) => _GroupPage(
          initial: index == null
              ? SmartGroup(
                  all: false,
                  children: const [
                    SmartCondition(
                      SmartField.added,
                      SmartOperator.within,
                      '30',
                    ),
                  ],
                )
              : group.children[index] as SmartGroup,
          depth: depth + 1,
        ),
      ),
    );
    if (value == null) return;
    if (index != null) {
      _replace(index, value);
    } else {
      onChanged(
        SmartGroup(all: group.all, children: [...group.children, value]),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          GlassDropdownField<bool>(
            initialValue: group.all,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Match'),
            items: const [
              DropdownMenuItem(value: true, child: Text('All conditions')),
              DropdownMenuItem(value: false, child: Text('Any condition')),
            ],
            onChanged: (value) =>
                onChanged(SmartGroup(all: value!, children: group.children)),
          ),
          if (group.children.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                title == 'Exclude'
                    ? 'No exclusions.'
                    : group.all
                    ? 'All songs are included.'
                    : 'Add a condition to match songs.',
              ),
            ),
          for (final (index, rule) in group.children.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                rule is SmartGroup
                    ? Icons.folder_outlined
                    : Icons.filter_alt_outlined,
              ),
              title: Text(rule.summary),
              subtitle: rule is SmartGroup ? const Text('Edit group') : null,
              trailing: IconButton(
                tooltip: 'Remove condition',
                onPressed: () => _replace(index, null),
                icon: const Icon(Icons.close_rounded),
              ),
              onTap: () => rule is SmartGroup
                  ? _group(context, index)
                  : _condition(context, index),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: group.children.length >= 50
                    ? null
                    : () => _condition(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add condition'),
              ),
              if (depth < 3)
                TextButton.icon(
                  onPressed: group.children.length >= 50
                      ? null
                      : () => _group(context),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Add group'),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _GroupPage extends StatefulWidget {
  const _GroupPage({required this.initial, required this.depth});
  final SmartGroup initial;
  final int depth;
  @override
  State<_GroupPage> createState() => _GroupPageState();
}

class _GroupPageState extends State<_GroupPage> {
  late SmartGroup _group = widget.initial;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: FloatingAppBar(
      title: 'Rule group',
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _group),
          child: const Text('Done'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Changes to this group apply when you choose Done.'),
        SmartRuleEditor(
          title: 'Conditions',
          group: _group,
          depth: widget.depth,
          onChanged: (value) => setState(() => _group = value),
        ),
      ],
    ),
  );
}

class _ConditionDialog extends StatefulWidget {
  const _ConditionDialog({required this.initial});
  final SmartCondition initial;
  @override
  State<_ConditionDialog> createState() => _ConditionDialogState();
}

class _ConditionDialogState extends State<_ConditionDialog> {
  late SmartField _field = widget.initial.field;
  late SmartOperator _operator = widget.initial.operator;
  late final _value = TextEditingController(text: widget.initial.value);
  String? _error;
  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  void _save() {
    final condition = SmartCondition(_field, _operator, _value.text.trim());
    try {
      condition.validate();
      Navigator.pop(context, condition);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => GlassAlertDialog(
    title: const Text('Condition'),
    content: SizedBox(
      width: 430,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GlassDropdownField<SmartField>(
              initialValue: _field,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Field'),
              items: SmartField.values
                  .map(
                    (field) => DropdownMenuItem(
                      value: field,
                      child: Text(field.label),
                    ),
                  )
                  .toList(),
              onChanged: (field) => setState(() {
                _field = field!;
                _operator = _field.operators.first;
                _value.text = _field.isDate
                    ? '30'
                    : _field.isNumber
                    ? '3'
                    : '';
                _error = null;
              }),
            ),
            const SizedBox(height: 16),
            GlassDropdownField<SmartOperator>(
              key: ValueKey(_field),
              initialValue: _operator,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Condition'),
              items: _field.operators
                  .map(
                    (operator) => DropdownMenuItem(
                      value: operator,
                      child: Text(operator.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _operator = value!),
            ),
            if (_operator.needsValue) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _value,
                maxLength: 200,
                keyboardType: _field.isNumber
                    ? TextInputType.number
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: 'Value',
                  suffixText: _field.isDate ? 'days' : null,
                  counterText: '',
                ),
                onSubmitted: (_) => _save(),
              ),
            ],
            if (_field == SmartField.played && _operator == SmartOperator.older)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('Also includes songs that have never been played.'),
              ),
            if (_field == SmartField.genre || _field == SmartField.year)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Missing metadata matches only “Is missing”. Genre checks every supplied genre; release year uses the song’s year tag. Older cached tracks gain these fields on the next library refresh.',
                ),
              ),
            if (_field == SmartField.rating)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Your rating: 0 is unrated, 1–5 are stars. Successful rating changes update playlists immediately.',
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Apply')),
    ],
  );
}
