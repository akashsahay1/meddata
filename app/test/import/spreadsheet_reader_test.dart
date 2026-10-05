import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_stock/services/import/sheet_table.dart';
import 'package:med_stock/services/import/spreadsheet_reader.dart';

const String _ns =
    'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"';
const String _rel =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// A minimal .xlsx: [sheets] are (name, sheetData rows XML, state).
Uint8List xlsx(
  List<(String, String, String)> sheets, {
  String? sharedStrings,
  String? styles,
  bool date1904 = false,
  bool withRootRels = true,
}) {
  final Archive a = Archive();
  void add(String path, String text) => a.add(ArchiveFile.string(path, text));
  if (withRootRels) {
    add('_rels/.rels',
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="$_rel/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>');
  }
  final StringBuffer wb = StringBuffer('<workbook $_ns>');
  if (date1904) wb.write('<workbookPr date1904="1"/>');
  wb.write('<sheets>');
  final StringBuffer rels = StringBuffer(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
  for (int i = 0; i < sheets.length; i++) {
    final (String name, String data, String state) = sheets[i];
    wb.write('<sheet name="$name" sheetId="${i + 1}" state="$state" r:id="rId${i + 1}"/>');
    rels.write('<Relationship Id="rId${i + 1}" Type="$_rel/worksheet" '
        'Target="worksheets/sheet${i + 1}.xml"/>');
    add('xl/worksheets/sheet${i + 1}.xml',
        '<?xml version="1.0" encoding="UTF-8"?><worksheet $_ns><sheetData>$data</sheetData></worksheet>');
  }
  wb.write('</sheets></workbook>');
  if (sharedStrings != null) {
    rels.write('<Relationship Id="rS" Type="$_rel/sharedStrings" Target="sharedStrings.xml"/>');
    add('xl/sharedStrings.xml', '<sst $_ns>$sharedStrings</sst>');
  }
  if (styles != null) {
    rels.write('<Relationship Id="rT" Type="$_rel/styles" Target="/xl/styles.xml"/>');
    add('xl/styles.xml', '<styleSheet $_ns>$styles</styleSheet>');
  }
  rels.write('</Relationships>');
  add('xl/workbook.xml', wb.toString());
  add('xl/_rels/workbook.xml.rels', rels.toString());
  return ZipEncoder().encodeBytes(a);
}

void main() {
  group('xlsx', () {
    const String styles = '<numFmts count="2">'
        '<numFmt numFmtId="164" formatCode="dd/mm/yyyy"/>'
        r'<numFmt numFmtId="165" formatCode="[$-409]mmm\-yy;@"/>'
        '</numFmts>'
        '<cellStyleXfs count="1"><xf numFmtId="14"/></cellStyleXfs>'
        '<cellXfs count="5"><xf numFmtId="0"/><xf numFmtId="14"/>'
        '<xf numFmtId="164"><alignment horizontal="left"/></xf>'
        '<xf numFmtId="165"/><xf numFmtId="2"/></cellXfs>';

    test('strings, numbers, dates, booleans and gaps', () {
      final Uint8List bytes = xlsx(
        <(String, String, String)>[
          ('Stock', '''
<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="D1" t="inlineStr"><is><t>Qty</t></is></c></row>
<row r="3"><c r="A3" t="s"><v>2</v></c><c r="B3" s="3"><v>46722</v></c><c r="C3" s="2"><v>46096</v></c><c r="D3"><v>10</v></c><c r="E3" s="4"><v>32.5</v></c><c r="F3" t="b"><v>1</v></c></row>
<row r="4"><c r="A4" t="str"><f>A3</f><v>Dolo 650</v></c><c r="B4" s="1"><v>46752</v></c><c r="C4" s="0"/><c r="D4"><v>8901234567890</v></c><c r="E4" t="e"><v>#N/A</v></c><c r="F4" t="s"><v>3</v></c></row>
<row><c t="s"><v>4</v></c><c><v>7</v></c></row>
''', 'visible'),
          ('Lookup', '<row r="1"><c r="A1"><v>1</v></c></row>', 'hidden'),
        ],
        sharedStrings: '<si><t>Item Name</t></si>'
            '<si><r><rPr><b/></rPr><t>Ex</t></r><r><t xml:space="preserve">p</t></r></si>'
            '<si><t>Dolo 650</t><rPh sb="0" eb="1"><t>X</t></rPh></si>'
            '<si><t>A&amp;B_x000D_</t></si>'
            '<si/>',
        styles: styles,
      );
      final List<SheetTable> sheets = SpreadsheetReader.read(bytes);
      expect(sheets.map((SheetTable s) => s.name), <String>['Stock'],
          reason: 'hidden sheets are left out');
      final List<List<Object?>> rows = sheets.single.rows;
      expect(rows, hasLength(5));
      expect(rows[0], <Object?>['Item Name', 'Exp', null, 'Qty']);
      expect(rows[1], isEmpty, reason: 'row 2 is blank; numbering is kept');
      expect(rows[2], <Object?>[
        'Dolo 650',
        CellDate(DateTime(2027, 12), hasDay: false),
        CellDate(DateTime(2026, 3, 15)),
        10,
        32.5,
        true,
      ]);
      expect(rows[3], <Object?>[
        'Dolo 650',
        CellDate(DateTime(2027, 12, 31)),
        null,
        8901234567890,
        '#N/A',
        'A&B\r',
      ]);
      expect(rows[4], <Object?>[null, 7],
          reason: 'cells without references follow on');
    });

    test('1904 date system, prefixed tags, no package rels', () {
      final Archive a = ZipDecoder().decodeBytes(xlsx(
        <(String, String, String)>[
          ('S', '', 'visible'),
        ],
        styles: '<cellXfs><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs>',
        date1904: true,
        withRootRels: false,
      ));
      final Archive b = Archive();
      for (final ArchiveFile f in a) {
        b.add(f.name == 'xl/worksheets/sheet1.xml'
            ? ArchiveFile.string(f.name,
                '<x:worksheet xmlns:x="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
                '<x:sheetData><x:row r="2"><x:c r="B2" s="1"><x:v>45290</x:v></x:c>'
                '<x:c r="C2" t="inlineStr"><x:is><x:t>hi</x:t></x:is></x:c></x:row>'
                '</x:sheetData></x:worksheet>')
            : ArchiveFile.bytes(f.name, f.content));
      }
      final SheetTable t = SpreadsheetReader.read(ZipEncoder().encodeBytes(b)).single;
      expect(t.rows[1], <Object?>[null, CellDate(DateTime(2027, 12, 31)), 'hi']);
    });

    test('files that are not workbooks', () {
      final Archive doc = Archive()
        ..add(ArchiveFile.string('word/document.xml', '<w/>'));
      expect(() => SpreadsheetReader.read(ZipEncoder().encodeBytes(doc)),
          throwsA(isA<ImportFileException>().having(
              (ImportFileException e) => e.message, 'message', contains('not an Excel'))));
      final Archive ods = Archive()
        ..add(ArchiveFile.string('content.xml', '<o/>'));
      expect(() => SpreadsheetReader.read(ZipEncoder().encodeBytes(ods)),
          throwsA(isA<ImportFileException>().having(
              (ImportFileException e) => e.message, 'message', contains('.ods'))));
      expect(
          () => SpreadsheetReader.read(
              Uint8List.fromList(<int>[0x50, 0x4B, 1, 2, 3, 4, 5, 6])),
          throwsA(isA<ImportFileException>()));
    });
  });

  group('csv', () {
    test('Excel-style CSV: BOM, semicolons, quotes, leading zeros, blank lines', () {
      final Uint8List bytes = Uint8List.fromList(utf8.encode(
          '\ufeffItem Name;Batch;Qty\r\nDolo 650;0012;10\r\n\r\n"Crocin; 500";C1;4\r\n'));
      final SheetTable t = SpreadsheetReader.read(bytes, fileName: 'C:\\x\\stock.csv').single;
      expect(t.name, 'stock');
      expect(t.rows[0], <Object?>['Item Name', 'Batch', 'Qty']);
      expect(t.rows[1], <Object?>['Dolo 650', '0012', '10']);
      expect(SheetTable.rowHasData(t.rows[2]), isFalse);
      expect(t.rows[3], <Object?>['Crocin; 500', 'C1', '4']);
    });

    test('comma separated with quoted commas', () {
      final SheetTable t = SpreadsheetReader.read(Uint8List.fromList(
              utf8.encode('Name,MRP\n"Vitamin B, C",1200.50\n')))
          .single;
      expect(t.rows[1], <Object?>['Vitamin B, C', '1200.50']);
    });

    test('text encodings', () {
      expect(
          SpreadsheetReader.decodeText(
              Uint8List.fromList(<int>[0x43, 0x61, 0x66, 0xE9])),
          'Café',
          reason: 'not UTF-8: read as Latin-1');
      final List<int> utf16 = <int>[0xFF, 0xFE];
      for (final int c in 'Qty\t5'.codeUnits) {
        utf16..add(c & 0xFF)..add(c >> 8);
      }
      expect(SpreadsheetReader.decodeText(Uint8List.fromList(utf16)), 'Qty\t5');
    });
  });

  test('unsupported files get a clear message', () {
    Matcher says(String text) => throwsA(isA<ImportFileException>().having(
        (ImportFileException e) => e.message, 'message', contains(text)));
    expect(() => SpreadsheetReader.read(Uint8List(0)), says('empty'));
    expect(
        () => SpreadsheetReader.read(Uint8List.fromList(
            <int>[0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0])),
        says('.xls'));
    expect(() => SpreadsheetReader.read(Uint8List.fromList(ascii.encode('%PDF-1.4'))),
        says('PDF'));
    expect(
        () => SpreadsheetReader.read(Uint8List.fromList(
            utf8.encode('<html><table><tr><td>x</td></tr></table></html>'))),
        says('web page'));
    expect(() => SpreadsheetReader.read(Uint8List.fromList(<int>[1, 0, 2, 0, 3])),
        says('not a CSV'));
  });
}
