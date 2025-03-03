import 'package:get/get.dart';

class TranslationHelpers {
  static String translateStatus(String status) {
    switch (status) {
      case 'completed':
        return 'completed'.tr;
      case 'processing':
        return 'processing'.tr;
      case 'failed':
        return 'failed'.tr;
      case 'pending':
        return 'pending'.tr;
      default:
        return 'unknown'.tr;
    }
  }

  static String translateVisibility(String visibility) {
    switch (visibility) {
      case 'public':
        return 'public'.tr;
      case 'private':
        return 'private'.tr;
      default:
        return 'unknown'.tr;
    }
  }

  static String translateDocType(String docType) {
    switch (docType) {
      case 'legal':
        return 'legal'.tr;
      case 'article':
        return 'article'.tr;
      case 'educational':
        return 'educational'.tr;
      case 'other':
        return 'other'.tr;
      default:
        return 'unknown'.tr;
    }
  }
}
