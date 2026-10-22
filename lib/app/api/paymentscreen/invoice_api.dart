import '../../../core/config/env.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/strapi.dart';
import 'billing_models.dart';
import 'payment_json.dart';
import 'wallet_models.dart';

/// Transaction invoices. The backend creates them automatically after a
/// payment (manual `POST /invoices` is rejected by backend policy).
abstract final class InvoiceApi {
  /// `GET /invoices` linked to [tx] by id or documentId; null when none yet.
  static Future<JsonMap?> fetchForTransaction(WalletTransaction tx) async {
    final id = tx.id;
    final docId = tx.documentId ?? id?.toString();
    if (id == null && docId == null) return null;
    final body = await ApiClient.get(
      '/invoices',
      query: {
        r'filters[$or][0][Related_Transaction][id][$eq]': ?id,
        r'filters[$or][1][Related_Transaction][documentId][$eq]': ?docId,
        'populate': '*',
      },
    );
    return paymentRows(body).firstOrNull;
  }

  /// Where the invoice PDF of [tx] stands: the populated invoice first, else
  /// a lookup (RN `downloadInvoicePdf`, minus opening the URL).
  static Future<InvoicePdfLookup> resolvePdf(WalletTransaction tx) async {
    final invoice = tx.invoices.firstOrNull ?? await fetchForTransaction(tx);
    if (invoice == null) {
      return const InvoicePdfLookup(InvoicePdfStatus.generating);
    }
    final url = pdfUrl(invoice);
    return url == null
        ? InvoicePdfLookup(InvoicePdfStatus.processing, invoice: invoice)
        : InvoicePdfLookup(InvoicePdfStatus.ready, url: url, invoice: invoice);
  }

  /// Absolute URL of `Invoice_PDF` (single media or a list), or null.
  static String? pdfUrl(JsonMap invoice) {
    final file = Strapi.list(invoice['Invoice_PDF']).firstOrNull;
    final formats = file?['formats'];
    final url =
        J.str(file?['url']) ?? (formats is Map ? J.str(formats['url']) : null);
    if (url == null) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${Env.apiBaseUrl}${url.startsWith('/') ? '' : '/'}$url';
  }

  /// Asks the backend to (re)build the PDF: `POST
  /// /invoices/generate-pdf/:id`, older backends `/invoices/:id/generate-pdf`.
  static Future<JsonMap> generatePdf(Object invoiceId) async {
    final id = Uri.encodeComponent('$invoiceId');
    try {
      return paymentData(
        await ApiClient.post('/invoices/generate-pdf/$id', data: const {}),
      );
    } on ApiException catch (e) {
      try {
        return paymentData(
          await ApiClient.post('/invoices/$id/generate-pdf', data: const {}),
        );
      } on ApiException {
        throw paymentError(e, 'payment:errors.invoice_failed');
      }
    }
  }
}
