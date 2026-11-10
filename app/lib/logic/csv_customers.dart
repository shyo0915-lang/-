class CsvCustomerRow {
  const CsvCustomerRow({
    required this.id,
    required this.name,
    required this.phone,
    required this.address,
    required this.memo,
    required this.contractDate,
    required this.unitPrice,
    required this.status,
    required this.ownerName,
    required this.lat,
    required this.lng,
  });

  final String id;
  final String name;
  final String phone;
  final String address;
  final String memo;
  final String contractDate;
  final int? unitPrice;
  final String status;
  final String ownerName;
  final double? lat;
  final double? lng;
}

class CsvImportResult {
  const CsvImportResult(this.rows, this.errors);
  final List<CsvCustomerRow> rows;
  final List<String> errors;
  bool get ok => errors.isEmpty;
}

const csvHeaders = [
  'id',
  'name',
  'phone',
  'address',
  'memo',
  'contract_date',
  'unit_price',
  'status',
  'owner_name',
  'lat',
  'lng',
];

String exportCustomersCsv(List<CsvCustomerRow> rows) {
  final lines = <String>[csvHeaders.join(',')];
  for (final row in rows) {
    lines.add([
      row.id,
      row.name,
      row.phone,
      row.address,
      row.memo,
      row.contractDate,
      row.unitPrice?.toString() ?? '',
      row.status,
      row.ownerName,
      row.lat?.toString() ?? '',
      row.lng?.toString() ?? '',
    ].map(_escape).join(','));
  }
  return '${lines.join('\n')}\n';
}

CsvImportResult importCustomersCsv(String csv) {
  final table = _parse(csv);
  if (table.isEmpty) return const CsvImportResult([], ['CSVが空です']);
  final header = table.first.map((cell) => cell.trim()).toList();
  final index = {for (var i = 0; i < header.length; i++) header[i]: i};
  for (final required in ['name', 'phone', 'address']) {
    if (!index.containsKey(required)) {
      return CsvImportResult(const [], ['見出し $required がありません']);
    }
  }
  final rows = <CsvCustomerRow>[];
  final errors = <String>[];
  for (var r = 1; r < table.length; r++) {
    final line = table[r];
    if (line.every((cell) => cell.trim().isEmpty)) continue;
    String cell(String key) {
      final at = index[key];
      if (at == null || at >= line.length) return '';
      return line[at].trim();
    }

    final name = cell('name');
    final phone = cell('phone');
    final address = cell('address');
    if (name.isEmpty || phone.isEmpty || address.isEmpty) {
      errors.add('${r + 1}行目: 顧客名・電話番号・住所は必須です');
      continue;
    }
    final priceRaw = cell('unit_price').replaceAll(',', '');
    int? price;
    if (priceRaw.isNotEmpty) {
      price = int.tryParse(priceRaw);
      if (price == null || price < 1) {
        errors.add('${r + 1}行目: 単価は1円以上の整数にしてください');
        continue;
      }
    }
    rows.add(
      CsvCustomerRow(
        id: cell('id'),
        name: name,
        phone: phone,
        address: address,
        memo: cell('memo'),
        contractDate: cell('contract_date'),
        unitPrice: price,
        status: cell('status'),
        ownerName: cell('owner_name'),
        lat: double.tryParse(cell('lat')),
        lng: double.tryParse(cell('lng')),
      ),
    );
  }
  return CsvImportResult(rows, errors);
}

String _escape(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n') || value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

List<List<String>> _parse(String csv) {
  final rows = <List<String>>[];
  final row = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  final text = csv.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        cell.write(char);
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      row.add(cell.toString());
      cell.clear();
    } else if (char == '\n') {
      row.add(cell.toString());
      cell.clear();
      rows.add(List<String>.from(row));
      row.clear();
    } else {
      cell.write(char);
    }
  }
  if (cell.isNotEmpty || row.isNotEmpty) {
    row.add(cell.toString());
    rows.add(row);
  }
  if (rows.isNotEmpty && rows.last.length == 1 && rows.last.single.isEmpty) {
    rows.removeLast();
  }
  return rows;
}
