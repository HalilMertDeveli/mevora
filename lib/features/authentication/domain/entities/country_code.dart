/// International dialing metadata used by phone auth. UI must not invent codes.
class CountryCode {
  const CountryCode({
    required this.country,
    required this.isoCode,
    required this.dialCode,
    required this.flag,
    this.minNationalLength = 6,
    this.maxNationalLength = 12,
  });

  final String country;
  final String isoCode;
  final String dialCode;
  final String flag;
  final int minNationalLength;
  final int maxNationalLength;

  String get dialPrefix => '+$dialCode';

  @override
  bool operator ==(Object other) {
    return other is CountryCode &&
        other.isoCode == isoCode &&
        other.dialCode == dialCode;
  }

  @override
  int get hashCode => Object.hash(isoCode, dialCode);
}

abstract final class CountryCodes {
  static const CountryCode turkey = CountryCode(
    country: 'Türkiye',
    isoCode: 'TR',
    dialCode: '90',
    flag: '🇹🇷',
    minNationalLength: 10,
    maxNationalLength: 10,
  );

  static const CountryCode germany = CountryCode(
    country: 'Almanya',
    isoCode: 'DE',
    dialCode: '49',
    flag: '🇩🇪',
    minNationalLength: 10,
    maxNationalLength: 11,
  );

  static const CountryCode unitedKingdom = CountryCode(
    country: 'Birleşik Krallık',
    isoCode: 'GB',
    dialCode: '44',
    flag: '🇬🇧',
    minNationalLength: 10,
    maxNationalLength: 10,
  );

  static const CountryCode unitedStates = CountryCode(
    country: 'Amerika Birleşik Devletleri',
    isoCode: 'US',
    dialCode: '1',
    flag: '🇺🇸',
    minNationalLength: 10,
    maxNationalLength: 10,
  );

  static const List<CountryCode> all = [
    turkey,
    germany,
    unitedKingdom,
    unitedStates,
    CountryCode(
      country: 'Fransa',
      isoCode: 'FR',
      dialCode: '33',
      flag: '🇫🇷',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Hollanda',
      isoCode: 'NL',
      dialCode: '31',
      flag: '🇳🇱',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'İtalya',
      isoCode: 'IT',
      dialCode: '39',
      flag: '🇮🇹',
      minNationalLength: 9,
      maxNationalLength: 11,
    ),
    CountryCode(
      country: 'İspanya',
      isoCode: 'ES',
      dialCode: '34',
      flag: '🇪🇸',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Avusturya',
      isoCode: 'AT',
      dialCode: '43',
      flag: '🇦🇹',
      minNationalLength: 10,
      maxNationalLength: 13,
    ),
    CountryCode(
      country: 'Belçika',
      isoCode: 'BE',
      dialCode: '32',
      flag: '🇧🇪',
      minNationalLength: 8,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'İsviçre',
      isoCode: 'CH',
      dialCode: '41',
      flag: '🇨🇭',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'İsveç',
      isoCode: 'SE',
      dialCode: '46',
      flag: '🇸🇪',
      minNationalLength: 7,
      maxNationalLength: 13,
    ),
    CountryCode(
      country: 'Norveç',
      isoCode: 'NO',
      dialCode: '47',
      flag: '🇳🇴',
      minNationalLength: 8,
      maxNationalLength: 8,
    ),
    CountryCode(
      country: 'Danimarka',
      isoCode: 'DK',
      dialCode: '45',
      flag: '🇩🇰',
      minNationalLength: 8,
      maxNationalLength: 8,
    ),
    CountryCode(
      country: 'Finlandiya',
      isoCode: 'FI',
      dialCode: '358',
      flag: '🇫🇮',
      minNationalLength: 5,
      maxNationalLength: 12,
    ),
    CountryCode(
      country: 'Polonya',
      isoCode: 'PL',
      dialCode: '48',
      flag: '🇵🇱',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Portekiz',
      isoCode: 'PT',
      dialCode: '351',
      flag: '🇵🇹',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Yunanistan',
      isoCode: 'GR',
      dialCode: '30',
      flag: '🇬🇷',
      minNationalLength: 10,
      maxNationalLength: 10,
    ),
    CountryCode(
      country: 'İrlanda',
      isoCode: 'IE',
      dialCode: '353',
      flag: '🇮🇪',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Kanada',
      isoCode: 'CA',
      dialCode: '1',
      flag: '🇨🇦',
      minNationalLength: 10,
      maxNationalLength: 10,
    ),
    CountryCode(
      country: 'Avustralya',
      isoCode: 'AU',
      dialCode: '61',
      flag: '🇦🇺',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Yeni Zelanda',
      isoCode: 'NZ',
      dialCode: '64',
      flag: '🇳🇿',
      minNationalLength: 8,
      maxNationalLength: 10,
    ),
    CountryCode(
      country: 'Birleşik Arap Emirlikleri',
      isoCode: 'AE',
      dialCode: '971',
      flag: '🇦🇪',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Suudi Arabistan',
      isoCode: 'SA',
      dialCode: '966',
      flag: '🇸🇦',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Hindistan',
      isoCode: 'IN',
      dialCode: '91',
      flag: '🇮🇳',
      minNationalLength: 10,
      maxNationalLength: 10,
    ),
    CountryCode(
      country: 'Japonya',
      isoCode: 'JP',
      dialCode: '81',
      flag: '🇯🇵',
      minNationalLength: 10,
      maxNationalLength: 10,
    ),
    CountryCode(
      country: 'Güney Kore',
      isoCode: 'KR',
      dialCode: '82',
      flag: '🇰🇷',
      minNationalLength: 9,
      maxNationalLength: 10,
    ),
    CountryCode(
      country: 'Brezilya',
      isoCode: 'BR',
      dialCode: '55',
      flag: '🇧🇷',
      minNationalLength: 10,
      maxNationalLength: 11,
    ),
    CountryCode(
      country: 'Meksika',
      isoCode: 'MX',
      dialCode: '52',
      flag: '🇲🇽',
      minNationalLength: 10,
      maxNationalLength: 10,
    ),
    CountryCode(
      country: 'Arjantin',
      isoCode: 'AR',
      dialCode: '54',
      flag: '🇦🇷',
      minNationalLength: 10,
      maxNationalLength: 10,
    ),
    CountryCode(
      country: 'Mısır',
      isoCode: 'EG',
      dialCode: '20',
      flag: '🇪🇬',
      minNationalLength: 10,
      maxNationalLength: 10,
    ),
    CountryCode(
      country: 'Güney Afrika',
      isoCode: 'ZA',
      dialCode: '27',
      flag: '🇿🇦',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Romanya',
      isoCode: 'RO',
      dialCode: '40',
      flag: '🇷🇴',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Çekya',
      isoCode: 'CZ',
      dialCode: '420',
      flag: '🇨🇿',
      minNationalLength: 9,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Macaristan',
      isoCode: 'HU',
      dialCode: '36',
      flag: '🇭🇺',
      minNationalLength: 8,
      maxNationalLength: 9,
    ),
    CountryCode(
      country: 'Singapur',
      isoCode: 'SG',
      dialCode: '65',
      flag: '🇸🇬',
      minNationalLength: 8,
      maxNationalLength: 8,
    ),
  ];

  static CountryCode? byIso(String isoCode) {
    final needle = isoCode.trim().toUpperCase();
    for (final country in all) {
      if (country.isoCode == needle) {
        return country;
      }
    }
    return null;
  }

  static CountryCode? byDialCode(String dialCode) {
    final digits = dialCode.replaceAll(RegExp(r'\D'), '');
    for (final country in all) {
      if (country.dialCode == digits) {
        return country;
      }
    }
    return null;
  }
}
