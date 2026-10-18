import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/features/dashboard/services/html_source_formatter.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';

void main() {
  test(
    'mobile expands text blocks without changing desktop output or rich text',
    () {
      for (final source in [
        '<p>Synthetic text</p>',
        '<p>Synthetic <strong>bold</strong> text</p>',
        '<div><p>One</p><p>Two <em>styled</em></p></div>',
        '<p><a href="fnotes://attachment/stable-id">@report.pdf</a> next</p>',
        '<p>Unicode தமிழ் 🌸 <b>bold</b><br/>next</p>',
        '<p> edge spaces <b>bold</b> </p>',
        '<pre>  keep\n whitespace</pre>',
        '<script>if (a < b) { x = ">"; }</script>',
      ]) {
        final desktop = formatHtmlSource(source);
        final mobile = formatExpandedHtmlSource(source);
        expect(formatHtmlSource(source), desktop);
        expect(formatExpandedHtmlSource(mobile), mobile, reason: source);
        expect(
          HtmlToDelta().convert(mobile).toJson(),
          HtmlToDelta().convert(source).toJson(),
          reason: source,
        );
      }
      expect(
        formatHtmlSource('<p>Synthetic text</p>'),
        '<p>Synthetic text</p>',
      );
      expect(
        formatExpandedHtmlSource('<p>Synthetic text</p>'),
        '<p>\n  Synthetic text\n</p>',
      );
    },
  );
  test(
    'structures mixed rich text with explicit breaks and preserves its delta',
    () {
      const source =
          '<p><span style="font-size: 0.75em">Synthetic intro</span><br/><br/><br/><em>Italic sample</em><br/><em>Next line</em><br/><strong>Bold</strong><u>Underlined</u></p>';
      final formatted = formatHtmlSource(source);
      expect(
        formatted,
        '<p>\n  <span style="font-size: 0.75em">Synthetic intro</span><br/>\n  <br/>\n  <br/>\n  <em>Italic sample</em><br/>\n  <em>Next line</em><br/>\n  <strong>Bold</strong><u>Underlined</u>\n</p>',
      );
      expect(formatHtmlSource(formatted), formatted);
      expect(
        HtmlToDelta().convert(formatted).toJson(),
        HtmlToDelta().convert(source).toJson(),
      );
    },
  );
  test(
    'mixed content preserves word spacing, edge spaces, nested breaks and blank lines',
    () {
      for (final source in [
        '<p> one <b>bold</b> two<br/>  next </p>',
        '<p><span>one<br/>two<br/>three</span><em>adjacent</em></p>',
        '<p><b>one</b><i>two</i></p>',
        '<p>plain<br/>next<br/><br/>last</p>',
        '<p><span>one</span> <em>two</em><br/> <u>three</u></p>',
        '<p>\u00a0one<br/>two\u00a0</p>',
        '<p>one<br/>\u00a0two</p>',
        '<section>\u00a0<div>Block</div></section>',
      ]) {
        final formatted = formatHtmlSource(source);
        expect(
          HtmlToDelta().convert(formatted).toJson(),
          HtmlToDelta().convert(source).toJson(),
          reason: source,
        );
        expect(formatHtmlSource(formatted), formatted, reason: source);
      }
    },
  );
  test('indents block structure and is idempotent', () {
    const source =
        '<section><h2>Sample</h2><div><p>Draft</p><p>Next</p></div></section>';
    final formatted = formatHtmlSource(source);
    expect(
      formatted,
      '<section>\n  <h2>Sample</h2>\n  <div>\n    <p>Draft</p>\n    <p>Next</p>\n  </div>\n</section>',
    );
    expect(formatHtmlSource(formatted), formatted);
  });
  test(
    'preserves inline spaces, entities, attributes and quoted angle brackets',
    () {
      const paragraph =
          '<p title="a > b" data-keep=original> a <b>bold</b>&nbsp;<i>word</i>  </p>';
      expect(
        formatHtmlSource('<div>$paragraph</div>'),
        '<div>\n  $paragraph\n</div>',
      );
      expect(
        formatHtmlSource('<span>one</span><span>two</span>'),
        '<span>one</span><span>two</span>',
      );
    },
  );
  test('keeps raw text and whitespace-sensitive source byte for byte', () {
    for (final content in [
      '<pre>  a\n b\n</pre>',
      '<code>a <b>b</b>  c</code>',
      '<textarea> a\n  b</textarea>',
      '<script>if (a < b) { x = ">"; }</script>',
      '<style>p { color: red; }\n</style>',
      '<div style="white-space: pre-wrap"><p>one</p>  <p>two</p></div>',
    ]) {
      expect(
        formatHtmlSource('<section>$content</section>'),
        contains(content),
      );
    }
  });
  test(
    'handles void tags, comments, document declarations and outer whitespace',
    () {
      const source =
          '\n<!DOCTYPE html><html><head><meta charset="utf-8"></head><body><!--keep--><p>a<br>b<img src="local"></p></body></html>\n';
      final result = formatHtmlSource(source);
      expect(result, contains('a<br>\n'));
      expect(result, contains('b<img src="local">'));
      expect(
        HtmlToDelta().convert(result).toJson(),
        HtmlToDelta().convert(source).toJson(),
      );
      expect(result, contains('<!--keep-->'));
      expect(result.startsWith('\n<!DOCTYPE html>\n<html>'), isTrue);
      expect(result.endsWith('</html>\n'), isTrue);
    },
  );
  test('rejects incomplete markup rather than repairing or losing it', () {
    for (final source in [
      '<div><p>lost</div>',
      '<p title="oops>',
      '<!--unfinished',
      '<script>x',
      '<p>unfinished',
    ]) {
      expect(() => formatHtmlSource(source), throwsFormatException);
    }
  });
  test('bounds nesting and preserves plain source', () {
    expect(formatHtmlSource(' plain text '), ' plain text ');
    expect(
      () => formatHtmlSource('${'<div>' * 257}${'</div>' * 257}'),
      throwsFormatException,
    );
  });
}
