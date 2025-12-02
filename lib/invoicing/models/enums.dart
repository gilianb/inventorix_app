enum InvoiceStatus { draft, sent, paid, overdue, cancelled }

enum InvoiceType { sale, purchase, creditNote }

InvoiceStatus invoiceStatusFromString(String value) {
  switch (value) {
    case 'draft':
      return InvoiceStatus.draft;
    case 'sent':
      return InvoiceStatus.sent;
    case 'paid':
      return InvoiceStatus.paid;
    case 'overdue':
      return InvoiceStatus.overdue;
    case 'cancelled':
      return InvoiceStatus.cancelled;
    default:
      return InvoiceStatus.draft;
  }
}

String invoiceStatusToString(InvoiceStatus status) {
  switch (status) {
    case InvoiceStatus.draft:
      return 'draft';
    case InvoiceStatus.sent:
      return 'sent';
    case InvoiceStatus.paid:
      return 'paid';
    case InvoiceStatus.overdue:
      return 'overdue';
    case InvoiceStatus.cancelled:
      return 'cancelled';
  }
}

InvoiceType invoiceTypeFromString(String value) {
  switch (value) {
    case 'sale':
      return InvoiceType.sale;
    case 'purchase':
      return InvoiceType.purchase;
    case 'credit_note':
      return InvoiceType.creditNote;
    default:
      return InvoiceType.sale;
  }
}

String invoiceTypeToString(InvoiceType type) {
  switch (type) {
    case InvoiceType.sale:
      return 'sale';
    case InvoiceType.purchase:
      return 'purchase';
    case InvoiceType.creditNote:
      return 'credit_note';
  }
}
