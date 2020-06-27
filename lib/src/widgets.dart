import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:org_flutter/src/controller.dart';
import 'package:org_flutter/src/highlight.dart';
import 'package:org_flutter/src/indent.dart';
import 'package:org_flutter/src/span.dart';
import 'package:org_flutter/src/theme.dart';
import 'package:org_flutter/src/util/util.dart';
import 'package:org_parser/org_parser.dart';

class OrgDocumentWidget extends StatelessWidget {
  const OrgDocumentWidget(
    this.document, {
    this.shrinkWrap = false,
    Key key,
  })  : assert(shrinkWrap != null),
        super(key: key);

  final OrgDocument document;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      controller: OrgController.of(context).scrollController,
      padding: OrgTheme.dataOf(context).rootPadding,
      shrinkWrap: shrinkWrap,
      children: <Widget>[
        if (document.content != null) OrgContentWidget(document.content),
        ...document.children.map((section) => OrgSectionWidget(section)),
        listBottomSafeArea(),
      ],
    );
  }
}

class OrgRootWidget extends StatelessWidget {
  const OrgRootWidget({
    this.child,
    this.style,
    this.lightTheme,
    this.darkTheme,
    this.onLinkTap,
    this.onLocalSectionLinkTap,
    this.onSectionLongPress,
    Key key,
  }) : super(key: key);

  final Widget child;
  final TextStyle style;
  final OrgThemeData lightTheme;
  final OrgThemeData darkTheme;
  final Function(String) onLinkTap;
  final Function(OrgSection) onLocalSectionLinkTap;
  final Function(OrgSection) onSectionLongPress;

  @override
  Widget build(BuildContext context) {
    final body = OrgTheme(
      light: lightTheme ?? OrgThemeData.light(),
      dark: darkTheme ?? OrgThemeData.dark(),
      child: OrgEvents(
        child: IdentityTextScale(child: child),
        onLinkTap: onLinkTap,
        onSectionLongPress: onSectionLongPress,
        onLocalSectionLinkTap: onLocalSectionLinkTap,
      ),
    );
    return style == null
        ? body
        : DefaultTextStyle.merge(
            style: style,
            child: body,
          );
  }
}

class OrgTheme extends InheritedWidget {
  const OrgTheme({
    @required Widget child,
    this.light,
    this.dark,
    Key key,
  }) : super(key: key, child: child);

  static OrgTheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OrgTheme>();

  static OrgThemeData dataOf(BuildContext context) {
    final theme = of(context);
    final brightness = MediaQuery.of(context).platformBrightness;
    switch (brightness) {
      case Brightness.dark:
        return theme.dark;
      case Brightness.light:
        return theme.light;
    }
    throw Exception('Unknown platform brightness: $brightness');
  }

  final OrgThemeData light;
  final OrgThemeData dark;

  @override
  bool updateShouldNotify(OrgTheme oldWidget) =>
      light != oldWidget.light || dark != oldWidget.dark;
}

class OrgEvents extends InheritedWidget {
  const OrgEvents({
    @required Widget child,
    this.onLinkTap,
    this.onLocalSectionLinkTap,
    this.onSectionLongPress,
    Key key,
  }) : super(key: key, child: child);

  final Function(String) onLinkTap;
  final Function(OrgSection) onLocalSectionLinkTap;
  final Function(OrgSection) onSectionLongPress;

  static OrgEvents of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OrgEvents>();

  void dispatchLinkTap(BuildContext context, String url) {
    if (!_handleLocalSectionLink(context, url)) {
      onLinkTap(url);
    }
  }

  bool _handleLocalSectionLink(BuildContext context, String url) {
    if (isOrgLocalSectionUrl(url)) {
      final sectionTitle = parseOrgLocalSectionUrl(url);
      final section = OrgController.of(context).sectionWithTitle(sectionTitle);
      if (section == null) {
        debugPrint('Failed to find local section with title "$sectionTitle"');
      } else {
        onLocalSectionLinkTap(section);
      }
      return true;
    }
    return false;
  }

  @override
  bool updateShouldNotify(OrgEvents oldWidget) =>
      onLinkTap != oldWidget.onLinkTap ||
      onSectionLongPress != oldWidget.onSectionLongPress;
}

class OrgSectionWidget extends StatelessWidget {
  const OrgSectionWidget(
    this.section, {
    this.root = false,
    this.shrinkWrap = false,
    Key key,
  })  : assert(section != null),
        assert(root != null),
        assert(shrinkWrap != null),
        super(key: key);
  final OrgSection section;
  final bool root;
  final bool shrinkWrap;

  // Whether the section is open "enough" to not show the trailing ellipsis
  bool _openEnough(OrgVisibilityState visibility) {
    switch (visibility) {
      case OrgVisibilityState.folded:
        return section.isEmpty;
      case OrgVisibilityState.contents:
        return section.content == null;
      case OrgVisibilityState.children:
      case OrgVisibilityState.subtree:
        return true;
    }
    throw Exception('Unknown visibility: $visibility');
  }

  @override
  Widget build(BuildContext context) {
    final visibilityListenable =
        OrgController.of(context).nodeFor(section)?.visibility;
    if (visibilityListenable == null) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<OrgVisibilityState>(
      valueListenable: visibilityListenable,
      builder: (context, visibility, child) => ListView(
        shrinkWrap: shrinkWrap || !root,
        physics:
            shrinkWrap || !root ? const NeverScrollableScrollPhysics() : null,
        // It's very important that the padding not be null here; otherwise
        // sections inside a root document will get some extraneous padding (see
        // discussion of padding behavior on ListView)
        padding: root ? OrgTheme.dataOf(context).rootPadding : EdgeInsets.zero,
        children: <Widget>[
          InkWell(
            child: OrgHeadlineWidget(
              section.headline,
              open: _openEnough(visibility),
            ),
            onTap: () => OrgController.of(context).cycleVisibilityOf(section),
            onLongPress: () =>
                OrgEvents.of(context)?.onSectionLongPress(section),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 100),
            transitionBuilder: (child, animation) =>
                SizeTransition(child: child, sizeFactor: animation),
            child: Column(
              key: ValueKey(visibility),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (section.content != null &&
                    (visibility == OrgVisibilityState.children ||
                        visibility == OrgVisibilityState.subtree))
                  OrgContentWidget(section.content),
                if (visibility != OrgVisibilityState.folded)
                  ...section.children.map((child) => OrgSectionWidget(child)),
              ],
            ),
          ),
          if (root) listBottomSafeArea(),
        ],
      ),
    );
  }
}

class OrgContentWidget extends StatelessWidget {
  const OrgContentWidget(
    this.content, {
    this.transformer,
    this.textAlign,
    Key key,
  }) : super(key: key);
  final OrgContentElement content;
  final Transformer transformer;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return FancySpanBuilder(
      builder: (context, spanBuilder) => Text.rich(
        spanBuilder.build(
          content,
          transformer: transformer ?? identityTransformer,
        ),
        textAlign: textAlign,
      ),
    );
  }
}

class OrgHeadlineWidget extends StatelessWidget {
  const OrgHeadlineWidget(this.headline, {@required this.open, Key key})
      : assert(open != null),
        super(key: key);
  final OrgHeadline headline;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final theme = OrgTheme.dataOf(context);
    final color = theme.levelColor(headline.level - 1);
    return DefaultTextStyle.merge(
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.bold,
        height: 1.8,
      ),
      child: FancySpanBuilder(
        builder: (context, spanBuilder) {
          final body = Text.rich(
            TextSpan(
              children: [
                spanBuilder.highlightedSpan(headline.stars),
                if (headline.keyword != null)
                  spanBuilder.highlightedSpan('${headline.keyword} ',
                      style: DefaultTextStyle.of(context).style.copyWith(
                          color: headline.keyword == 'DONE'
                              ? theme.doneColor
                              : theme.todoColor)),
                if (headline.priority != null)
                  spanBuilder.highlightedSpan('${headline.priority} ',
                      style: DefaultTextStyle.of(context)
                          .style
                          .copyWith(color: theme.priorityColor)),
                if (headline.title != null)
                  spanBuilder.build(
                    headline.title,
                    transformer: (elem, text) {
                      if (elem == headline.title.children.last) {
                        return text.trimRight();
                      } else {
                        return text;
                      }
                    },
                  ),
                if (!open && headline.tags.isEmpty) const TextSpan(text: '...'),
              ],
            ),
          );
          if (headline.tags.isEmpty) {
            return body;
          } else {
            return LayoutBuilder(
              builder: (context, constraints) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: body),
                    const SizedBox(width: 16),
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth / 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text.rich(
                              spanBuilder.highlightedSpan(
                                  ' :${headline.tags.join(':')}:'),
                              overflow: TextOverflow.fade,
                              softWrap: false,
                            ),
                          ),
                          if (!open) const Text('...'),
                        ],
                      ),
                    ),
                  ],
                );
              },
            );
          }
        },
      ),
    );
  }
}

class IdentityTextScale extends StatelessWidget {
  const IdentityTextScale({@required this.child, Key key})
      : assert(child != null),
        super(key: key);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaleFactor: 1),
      child: child,
    );
  }
}

class OrgBlockWidget extends StatefulWidget {
  const OrgBlockWidget(this.block, {Key key})
      : assert(block != null),
        super(key: key);
  final OrgBlock block;

  @override
  _OrgBlockWidgetState createState() => _OrgBlockWidgetState();
}

class _OrgBlockWidgetState extends State<OrgBlockWidget>
    with OpenCloseable<OrgBlockWidget> {
  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final metaStyle =
        defaultStyle.copyWith(color: OrgTheme.dataOf(context).metaColor);
    final hideMarkup = OrgController.of(context).hideMarkup;
    return IndentBuilder(
      widget.block.indent,
      builder: (context, totalIndentSize) {
        return ValueListenableBuilder<bool>(
          valueListenable: openListenable,
          builder: (context, open, child) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (!hideMarkup)
                InkWell(
                  child: Text(
                    widget.block.header.trimRight() + (open ? '' : '...'),
                    style: metaStyle,
                  ),
                  onTap: () => openListenable.value = !openListenable.value,
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 100),
                transitionBuilder: (child, animation) =>
                    SizeTransition(child: child, sizeFactor: animation),
                child: open ? child : const SizedBox.shrink(),
              ),
              // Remove two linebreaks because we introduce two by splitting the
              // text into two widgets in this Column
              Text(
                removeTrailingLineBreak(
                  removeTrailingLineBreak(widget.block.trailing),
                ),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _body(
                context,
                (_, string) =>
                    removeTrailingLineBreak(deindent(string, totalIndentSize)),
              ),
              if (!hideMarkup)
                Text(
                  deindent(widget.block.footer, totalIndentSize),
                  style: metaStyle,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _body(BuildContext context, Transformer transformer) {
    final block = widget.block;
    Widget body;
    if (block is OrgSrcBlock) {
      final code = widget.block.body as OrgPlainText;
      if (supportedSrcLanguage(block.language)) {
        body = buildSrcHighlight(
          context,
          code: transformer(code, code.content),
          language: block.language,
        );
      } else {
        body = OrgContentWidget(
          OrgMarkup.just(code.content, OrgStyle.code),
          transformer: transformer,
        );
      }
    } else {
      body = OrgContentWidget(
        block.body,
        transformer: transformer,
      );
    }
    // TODO(aaron): Better distinguish "greater block" from regular block
    return block.body is OrgContent
        ? body
        : SingleChildScrollView(
            child: body,
            scrollDirection: Axis.horizontal,
            physics: const AlwaysScrollableScrollPhysics(),
          );
  }
}

class OrgMetaWidget extends StatelessWidget {
  const OrgMetaWidget(this.meta, {Key key})
      : assert(meta != null),
        super(key: key);
  final OrgMeta meta;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: TextStyle(color: OrgTheme.dataOf(context).metaColor),
      child: IndentBuilder(
        meta.indent,
        builder: (context, _) {
          return FancySpanBuilder(
            builder: (context, spanBuilder) => Text.rich(
              TextSpan(
                children: _spans(context, spanBuilder).toList(growable: false),
              ),
            ),
          );
        },
      ),
    );
  }

  Iterable<InlineSpan> _spans(
      BuildContext context, OrgSpanBuilder builder) sync* {
    yield builder.highlightedSpan(meta.keyword);
    final trailing = removeTrailingLineBreak(meta.trailing);
    if (trailing.isNotEmpty) {
      yield builder.highlightedSpan(trailing);
    }
  }
}

class OrgTableWidget extends StatelessWidget {
  const OrgTableWidget(this.table, {Key key})
      : assert(table != null),
        super(key: key);
  final OrgTable table;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: TextStyle(color: OrgTheme.dataOf(context).tableColor),
      child: ConstrainedBox(
        // Ensure that table takes up entire width (can't have tables
        // side-by-side)
        constraints: const BoxConstraints.tightFor(width: double.infinity),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Row(
            children: <Widget>[
              Text(table.indent),
              Column(
                  children: _columnChildren(context).toList(growable: false)),
            ],
          ),
        ),
      ),
    );
  }

  Iterable<Widget> _columnChildren(BuildContext context) sync* {
    final tableColor = OrgTheme.dataOf(context).tableColor;
    final borderSide = BorderSide(color: tableColor);
    yield Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      border: TableBorder(
        verticalInside: borderSide,
        left: borderSide,
        right: table.rectangular ? borderSide : BorderSide.none,
      ),
      children: _tableRows(borderSide).toList(growable: false),
    );
    if (table.trailing.isNotEmpty) {
      yield Text(removeTrailingLineBreak(table.trailing));
    }
  }

  Iterable<TableRow> _tableRows(BorderSide borderSide) sync* {
    final columnCount = table.columnCount;
    final numerical = List<bool>.generate(columnCount, table.columnIsNumeric);
    for (var i = 0; i < table.rows.length; i++) {
      final row = table.rows[i];
      final nextRow = i + 1 < table.rows.length ? table.rows[i + 1] : null;
      if (row is OrgTableCellRow) {
        // Peek at next row, add bottom border if it's a divider
        final decoration = nextRow is OrgTableDividerRow
            ? BoxDecoration(border: Border(bottom: borderSide))
            : null;
        yield TableRow(
          decoration: decoration,
          children: [
            for (var j = 0; j < columnCount; j++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: j < row.cellCount
                    ? OrgContentWidget(
                        row.cells[j],
                        textAlign: numerical[j] ? TextAlign.right : null,
                      )
                    : const SizedBox.shrink(),
              ),
          ],
        );
      }
    }
  }
}

class OrgFixedWidthAreaWidget extends StatelessWidget {
  const OrgFixedWidthAreaWidget(this.fixedWidthArea, {Key key})
      : assert(fixedWidthArea != null),
        super(key: key);
  final OrgFixedWidthArea fixedWidthArea;

  @override
  Widget build(BuildContext context) {
    return IndentBuilder(
      fixedWidthArea.indent,
      builder: (context, totalIndentSize) {
        return DefaultTextStyle.merge(
          style: TextStyle(color: OrgTheme.dataOf(context).codeColor),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const AlwaysScrollableScrollPhysics(),
            child: FancySpanBuilder(
              builder: (context, spanBuilder) => Text.rich(
                spanBuilder.highlightedSpan(
                  deindent(fixedWidthArea.content, totalIndentSize) +
                      removeTrailingLineBreak(fixedWidthArea.trailing),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class OrgParagraphWidget extends StatelessWidget {
  const OrgParagraphWidget(this.paragraph, {Key key})
      : assert(paragraph != null),
        super(key: key);
  final OrgParagraph paragraph;

  @override
  Widget build(BuildContext context) {
    return IndentBuilder(
      paragraph.indent,
      builder: (context, totalIndentSize) {
        return OrgContentWidget(
          paragraph.body,
          transformer: (elem, content) {
            final isLast = elem == paragraph.body.children.last;
            final reflowed = reflowText(
              deindent(content, totalIndentSize),
              end: isLast,
            );
            return isLast ? removeTrailingLineBreak(reflowed) : reflowed;
          },
        );
      },
    );
  }
}

class OrgListWidget extends StatelessWidget {
  const OrgListWidget(this.list, {Key key})
      : assert(list != null),
        super(key: key);
  final OrgList list;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _children.toList(growable: false),
    );
  }

  Iterable<Widget> get _children sync* {
    for (final item in list.items) {
      yield OrgListItemWidget(item);
    }
    final trailing = removeTrailingLineBreak(list.trailing);
    if (trailing.isNotEmpty) {
      yield Text(trailing);
    }
  }
}

class OrgListItemWidget extends StatelessWidget {
  const OrgListItemWidget(this.item, {Key key})
      : assert(item != null),
        super(key: key);
  final OrgListItem item;

  @override
  Widget build(BuildContext context) {
    return IndentBuilder(
      '${item.indent}${item.bullet}',
      builder: (context, _) => FancySpanBuilder(
        builder: (context, spanBuilder) => Text.rich(
          TextSpan(
            children: _spans(context, spanBuilder).toList(growable: false),
          ),
        ),
      ),
    );
  }

  Iterable<InlineSpan> _spans(
    BuildContext context,
    OrgSpanBuilder builder,
  ) sync* {
    final item = this.item;
    if (item is OrgListOrderedItem && item.counterSet != null) {
      yield builder.highlightedSpan(
        '${item.counterSet} ',
        style: DefaultTextStyle.of(context)
            .style
            .copyWith(fontWeight: FontWeight.bold),
      );
    }
    if (item.checkbox != null) {
      yield builder.highlightedSpan(
        '${item.checkbox} ',
        style: DefaultTextStyle.of(context)
            .style
            .copyWith(fontWeight: FontWeight.bold),
      );
    }
    if (item is OrgListUnorderedItem && item.tag != null) {
      final style = DefaultTextStyle.of(context)
          .style
          .copyWith(fontWeight: FontWeight.bold);
      yield TextSpan(children: [
        builder.build(item.tag, style: style),
        builder.highlightedSpan(item.tagDelimiter, style: style),
      ]);
    }
    if (item.body != null) {
      yield builder.build(item.body, transformer: (elem, content) {
        final isLast = item.body.children.last == elem;
        final reflowed = reflowText(
          content,
          end: isLast,
        );
        return isLast ? removeTrailingLineBreak(reflowed) : reflowed;
      });
    }
  }
}

class OrgDrawerWidget extends StatefulWidget {
  const OrgDrawerWidget(this.drawer, {Key key})
      : assert(drawer != null),
        super(key: key);
  final OrgDrawer drawer;

  @override
  _OrgDrawerWidgetState createState() => _OrgDrawerWidgetState();
}

class _OrgDrawerWidgetState extends State<OrgDrawerWidget>
    with OpenCloseable<OrgDrawerWidget> {
  @override
  bool get defaultOpen => false;

  @override
  Widget build(BuildContext context) {
    final defaultStyle = DefaultTextStyle.of(context).style;
    final drawerStyle =
        defaultStyle.copyWith(color: OrgTheme.dataOf(context).drawerColor);
    return IndentBuilder(
      widget.drawer.indent,
      builder: (context, totalIndentSize) {
        return ValueListenableBuilder<bool>(
          valueListenable: openListenable,
          builder: (context, open, child) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              InkWell(
                child: Text(
                  widget.drawer.header.trimRight() + (open ? '' : '...'),
                  style: drawerStyle,
                ),
                onTap: () => openListenable.value = !openListenable.value,
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 100),
                transitionBuilder: (child, animation) =>
                    SizeTransition(child: child, sizeFactor: animation),
                child: open ? child : const SizedBox.shrink(),
              ),
              // Remove two linebreaks because we introduce two by splitting the
              // text into two widgets in this Column
              Text(
                removeTrailingLineBreak(
                  removeTrailingLineBreak(widget.drawer.trailing),
                ),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _body((_, string) =>
                  removeTrailingLineBreak(deindent(string, totalIndentSize))),
              Text(
                deindent(widget.drawer.footer, totalIndentSize),
                style: drawerStyle,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _body(Transformer transformer) {
    final body = OrgContentWidget(
      widget.drawer.body,
      transformer: transformer,
    );
    // TODO(aaron): Better distinguish "greater block" from regular block
    return widget.drawer.body is OrgContent
        ? body
        : SingleChildScrollView(
            child: body,
            scrollDirection: Axis.horizontal,
            physics: const AlwaysScrollableScrollPhysics(),
          );
  }
}

class OrgPropertyWidget extends StatelessWidget {
  const OrgPropertyWidget(this.property, {Key key})
      : assert(property != null),
        super(key: key);
  final OrgProperty property;

  @override
  Widget build(BuildContext context) {
    return IndentBuilder(
      property.indent,
      builder: (context, _) {
        return FancySpanBuilder(
          builder: (context, spanBuilder) => Text.rich(
            TextSpan(
              children: _spans(context, spanBuilder).toList(growable: false),
            ),
          ),
        );
      },
    );
  }

  Iterable<InlineSpan> _spans(
      BuildContext context, OrgSpanBuilder builder) sync* {
    yield builder.highlightedSpan(
      property.key,
      style: DefaultTextStyle.of(context)
          .style
          .copyWith(color: OrgTheme.dataOf(context).keywordColor),
    );
    yield builder.highlightedSpan(property.value);
    final trailing = removeTrailingLineBreak(property.trailing);
    if (trailing.isNotEmpty) {
      yield builder.highlightedSpan(trailing);
    }
  }
}
