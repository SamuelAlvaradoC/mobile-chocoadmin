import 'package:intl/intl.dart';

// ── Moneda ──────────────────────────────────────────────────────────────────
// Pesos colombianos como "$43.000". NumberFormat.currency(locale: 'es_CO')
// por sí solo pone el símbolo al final ("43.000 $"); el customPattern lo deja
// adelante, igual que la web.
final NumberFormat fmtCop = NumberFormat.currency(
  locale: 'es_CO',
  symbol: '\$',
  decimalDigits: 0,
  customPattern: '¤#,##0',
);

// ── Fechas en hora Colombia ─────────────────────────────────────────────────
// La API devuelve timestamps en UTC ("2026-10-12T21:11:32.715Z"). Formatear el
// DateTime parseado tal cual muestra la hora UTC (21:11 en vez de 4:11 PM), y
// toLocal() depende de la zona del celular -- así que se convierte siempre de
// forma explícita a UTC-5 (Colombia no tiene horario de verano).
const Duration _offsetColombia = Duration(hours: 5);

/// Parsea un timestamp de la API como instante UTC. Si el texto viene sin zona
/// (sin "Z" ni offset), se interpreta como UTC -- así se guardan en la base.
/// Solo para timestamps: una fecha suelta 'yyyy-MM-dd' no es un instante.
DateTime? parseFechaApi(Object? raw) {
  if (raw == null) return null;
  final texto = raw.toString().trim();
  if (texto.isEmpty) return null;
  final dt = DateTime.tryParse(texto);
  if (dt == null) return null;
  if (dt.isUtc) return dt;
  return DateTime.utc(dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, dt.millisecond, dt.microsecond);
}

/// El mismo instante con los campos (year, hour...) en hora Colombia, listo
/// para pasarle a DateFormat. Llamar UNA sola vez sobre un instante real
/// (de parseFechaApi o DateTime.now()), nunca sobre un resultado de esta función.
DateTime aColombia(DateTime instante) => instante.toUtc().subtract(_offsetColombia);

DateTime ahoraColombia() => aColombia(DateTime.now());

/// Fecha de hoy en Colombia como 'yyyy-MM-dd' (para filtros "hoy" de la API):
/// a las 8 PM Colombia sigue siendo hoy aunque en UTC ya sea mañana.
String hoyColombiaIso() => DateFormat('yyyy-MM-dd').format(ahoraColombia());

/// "4:11 PM"
String horaColombia(DateTime instante) {
  final co = aColombia(instante);
  final h12 = co.hour % 12 == 0 ? 12 : co.hour % 12;
  return '$h12:${co.minute.toString().padLeft(2, '0')} ${co.hour < 12 ? 'AM' : 'PM'}';
}

/// Fecha con el patrón dado, en hora Colombia (ej. 'dd/MM/yyyy', 'dd MMM').
String fechaColombia(DateTime instante, String patron) =>
    DateFormat(patron, 'es_CO').format(aColombia(instante));

/// "12/10/2026 4:11 PM"
String fechaHoraColombia(DateTime instante, {String patronFecha = 'dd/MM/yyyy'}) =>
    '${fechaColombia(instante, patronFecha)} ${horaColombia(instante)}';
