import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:org_flutter/org_flutter.dart';
import 'package:org_flutter/src/util.dart';

class SpanBuilder {
  SpanBuilder(this.context, {this.highlight}) : assert(context != null);

  final BuildContext context;
  final Pattern highlight;

  InlineSpan build(
    OrgContentElement element,
    Function(GestureRecognizer) registerRecognizer,
  ) {
    assert(registerRecognizer != null);
    if (element is OrgPlainText) {
      return highlightedSpan(element.content);
    } else if (element is OrgMarkup) {
      return highlightedSpan(
        element.content,
        style: OrgTheme.dataOf(context).fontStyleForOrgStyle(
          DefaultTextStyle.of(context).style,
          element.style,
        ),
      );
    } else if (element is OrgKeyword) {
      return highlightedSpan(
        element.content,
        style: DefaultTextStyle.of(context)
            .style
            .copyWith(color: OrgTheme.dataOf(context).keywordColor),
      );
    } else if (element is OrgLink) {
      final linkDispatcher =
          OrgEvents.of(context)?.dispatchLinkTap ?? (_, __) {};
      final recognizer = TapGestureRecognizer()
        ..onTap = () => linkDispatcher(context, element.location);
      registerRecognizer(recognizer);
      final visibleContent = element.description ?? element.location;
      return highlightedSpan(
        visibleContent,
        recognizer: recognizer,
        style: DefaultTextStyle.of(context).style.copyWith(
              color: OrgTheme.dataOf(context).linkColor,
              decoration: TextDecoration.underline,
            ),
        charWrap: true,
      );
    } else if (element is OrgMeta) {
      return highlightedSpan(
        element.content,
        style: DefaultTextStyle.of(context)
            .style
            .copyWith(color: OrgTheme.dataOf(context).metaColor),
      );
    } else if (element is OrgTimestamp) {
      return highlightedSpan(
        element.content,
        style: DefaultTextStyle.of(context).style.copyWith(
              color: OrgTheme.dataOf(context).dateColor,
              decoration: TextDecoration.underline,
            ),
      );
    } else if (element is OrgBlock) {
      return WidgetSpan(
          child: IdentityTextScale(child: OrgBlockWidget(element)));
    } else if (element is OrgTable) {
      return WidgetSpan(
          child: IdentityTextScale(child: OrgTableWidget(element)));
    } else if (element is OrgFixedWidthArea) {
      return WidgetSpan(
          child: IdentityTextScale(child: OrgFixedWidthAreaWidget(element)));
    } else if (element is OrgList) {
      return TextSpan(children: [
        for (final item in element.items) build(item, registerRecognizer),
      ]);
    } else if (element is OrgListItem) {
      return TextSpan(children: [
        TextSpan(text: element.indent),
        TextSpan(text: element.bullet),
        if (element is OrgListOrderedItem && element.counterSet != null)
          TextSpan(text: '${element.counterSet} '),
        if (element.checkbox != null)
          TextSpan(
            text: '${element.checkbox} ',
            style: DefaultTextStyle.of(context)
                .style
                .copyWith(fontWeight: FontWeight.bold),
          ),
        if (element is OrgListUnorderedItem && element.tag != null)
          TextSpan(
            text: element.tag,
            style: DefaultTextStyle.of(context)
                .style
                .copyWith(fontWeight: FontWeight.bold),
          ),
        if (element.body != null) build(element.body, registerRecognizer),
      ]);
    } else if (element is OrgContent) {
      return TextSpan(
          children: element.children
              .map((child) => build(child, registerRecognizer))
              .toList(growable: false));
    } else {
      throw Exception('Unknown OrgContentElement type: $element');
    }
  }

  InlineSpan highlightedSpan(
    String text, {
    TextStyle style,
    GestureRecognizer recognizer,
    bool charWrap = false,
  }) {
    if (emptyPattern(highlight)) {
      return TextSpan(
        text: charWrap ? characterWrappable(text) : text,
        style: style,
        recognizer: recognizer,
      );
    } else {
      final realStyle = style ?? DefaultTextStyle.of(context).style;
      return TextSpan(
        style: realStyle,
        recognizer: recognizer,
        children: tokenizeTextSpan(
          text,
          highlight,
          realStyle.copyWith(
            backgroundColor: OrgTheme.dataOf(context).highlightColor,
          ),
          charWrap ? characterWrappable : (x) => x,
        ).toList(growable: false),
      );
    }
  }
}

Iterable<InlineSpan> tokenizeTextSpan(
  String text,
  Pattern pattern,
  TextStyle matchStyle,
  String Function(String) transform,
) sync* {
  var lastEnd = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > lastEnd) {
      yield TextSpan(text: transform(text.substring(lastEnd, match.start)));
    }
    yield TextSpan(text: transform(match.group(0)), style: matchStyle);
    lastEnd = match.end;
  }
  if (lastEnd < text.length) {
    yield TextSpan(text: transform(text.substring(lastEnd, text.length)));
  }
}
