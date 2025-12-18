import 'package:flutter/material.dart';
import '../../edit/edit_page.dart' show EditItemsDialog;

class EditListingDialog {
  static Future<bool?> show(
    BuildContext context, {
    required int productId,
    required String status,
    required int availableQty,
    required Map<String, dynamic> initialSample,
  }) {
    return EditItemsDialog.show(
      context,
      productId: productId,
      status: status,
      availableQty: availableQty,
      initialSample: initialSample,
    );
  }
}
