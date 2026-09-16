import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration animationDuration;
  final Duration backDuration;
  final Duration pauseDuration;
  final TextAlign textAlign;

  const MarqueeText({
    Key? key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.left,
    this.animationDuration = const Duration(seconds: 5),
    this.backDuration = const Duration(milliseconds: 800),
    this.pauseDuration = const Duration(seconds: 1),
  }) : super(key: key);

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollText());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollText() async {
    while (_scrollController.hasClients) {
      await Future.delayed(widget.pauseDuration);
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0) {
        await _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: widget.animationDuration,
          curve: Curves.linear,
        );
        await Future.delayed(widget.pauseDuration);
        if (_scrollController.hasClients) {
          await _scrollController.animateTo(
            0.0,
            duration: widget.backDuration,
            curve: Curves.easeOut,
          );
        }
      } else {
        await Future.delayed(widget.pauseDuration);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: 1,
        overflow: TextOverflow.visible,
      ),
    );
  }
}
