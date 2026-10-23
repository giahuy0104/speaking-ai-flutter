import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

Future<void> ensureVocabularyEntryVisible(BuildContext context) {
  final renderObject = context.findRenderObject();
  final viewport = renderObject == null
      ? null
      : RenderAbstractViewport.maybeOf(renderObject);
  final scrollable = Scrollable.maybeOf(context);
  if (viewport == null || scrollable == null) return Future<void>.value();
  final aboveViewport =
      viewport.getOffsetToReveal(renderObject!, 0).offset <
      scrollable.position.pixels;
  return Scrollable.ensureVisible(
    context,
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
    alignmentPolicy: aboveViewport
        ? ScrollPositionAlignmentPolicy.keepVisibleAtStart
        : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
  );
}
