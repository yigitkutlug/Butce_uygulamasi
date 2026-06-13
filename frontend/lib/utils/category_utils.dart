import '../localization/app_localizer.dart';
import '../state/app_controller.dart';

String localizeCategory(AppController controller, String rawCategory) {
  final normalized = rawCategory.trim().toLowerCase();
  switch (normalized) {
    case 'food':
      return AppLocalizer.text(controller, 'food');
    case 'market':
      return AppLocalizer.text(controller, 'market');
    case 'transport':
      return AppLocalizer.text(controller, 'transport');
    case 'bills':
      return AppLocalizer.text(controller, 'bills');
    case 'entertainment':
      return AppLocalizer.text(controller, 'entertainment');
    case 'other':
      return AppLocalizer.text(controller, 'other');
    case 'salary':
      return AppLocalizer.text(controller, 'salary');
    case 'additional income':
      return AppLocalizer.text(controller, 'additionalIncome');
    case 'scholarship':
      return AppLocalizer.text(controller, 'scholarship');
    case 'freelance':
      return AppLocalizer.text(controller, 'freelance');
    case 'investment':
      return AppLocalizer.text(controller, 'investment');
    case 'rental income':
      return AppLocalizer.text(controller, 'rentalIncome');
    case 'gift':
      return AppLocalizer.text(controller, 'giftIncome');
    case 'other income':
      return AppLocalizer.text(controller, 'otherIncome');
    case 'general income':
      return AppLocalizer.text(controller, 'generalIncome');
    default:
      return rawCategory;
  }
}
