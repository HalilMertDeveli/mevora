class CountryDialCode {
  const CountryDialCode({
    required this.name,
    required this.iso2,
    required this.dialCode,
    required this.flag,
  });

  final String name;
  final String iso2;
  final String dialCode;
  final String flag;
}

/// International dial codes. Includes +90 Turkey and is not Turkey-only.
abstract final class CountryDialCodes {
  static const CountryDialCode turkey = CountryDialCode(
    name: 'Turkey',
    iso2: 'TR',
    dialCode: '90',
    flag: '🇹🇷',
  );

  static const List<CountryDialCode> all = [
    CountryDialCode(name: 'United States', iso2: 'US', dialCode: '1', flag: '🇺🇸'),
    CountryDialCode(name: 'United Kingdom', iso2: 'GB', dialCode: '44', flag: '🇬🇧'),
    turkey,
    CountryDialCode(name: 'Germany', iso2: 'DE', dialCode: '49', flag: '🇩🇪'),
    CountryDialCode(name: 'France', iso2: 'FR', dialCode: '33', flag: '🇫🇷'),
    CountryDialCode(name: 'Netherlands', iso2: 'NL', dialCode: '31', flag: '🇳🇱'),
    CountryDialCode(name: 'Italy', iso2: 'IT', dialCode: '39', flag: '🇮🇹'),
    CountryDialCode(name: 'Spain', iso2: 'ES', dialCode: '34', flag: '🇪🇸'),
    CountryDialCode(name: 'Canada', iso2: 'CA', dialCode: '1', flag: '🇨🇦'),
    CountryDialCode(name: 'Australia', iso2: 'AU', dialCode: '61', flag: '🇦🇺'),
    CountryDialCode(name: 'Brazil', iso2: 'BR', dialCode: '55', flag: '🇧🇷'),
    CountryDialCode(name: 'India', iso2: 'IN', dialCode: '91', flag: '🇮🇳'),
    CountryDialCode(name: 'Japan', iso2: 'JP', dialCode: '81', flag: '🇯🇵'),
    CountryDialCode(name: 'South Korea', iso2: 'KR', dialCode: '82', flag: '🇰🇷'),
    CountryDialCode(name: 'United Arab Emirates', iso2: 'AE', dialCode: '971', flag: '🇦🇪'),
    CountryDialCode(name: 'Saudi Arabia', iso2: 'SA', dialCode: '966', flag: '🇸🇦'),
    CountryDialCode(name: 'Egypt', iso2: 'EG', dialCode: '20', flag: '🇪🇬'),
    CountryDialCode(name: 'Greece', iso2: 'GR', dialCode: '30', flag: '🇬🇷'),
    CountryDialCode(name: 'Poland', iso2: 'PL', dialCode: '48', flag: '🇵🇱'),
    CountryDialCode(name: 'Sweden', iso2: 'SE', dialCode: '46', flag: '🇸🇪'),
    CountryDialCode(name: 'Norway', iso2: 'NO', dialCode: '47', flag: '🇳🇴'),
    CountryDialCode(name: 'Denmark', iso2: 'DK', dialCode: '45', flag: '🇩🇰'),
    CountryDialCode(name: 'Finland', iso2: 'FI', dialCode: '358', flag: '🇫🇮'),
    CountryDialCode(name: 'Portugal', iso2: 'PT', dialCode: '351', flag: '🇵🇹'),
    CountryDialCode(name: 'Mexico', iso2: 'MX', dialCode: '52', flag: '🇲🇽'),
    CountryDialCode(name: 'Argentina', iso2: 'AR', dialCode: '54', flag: '🇦🇷'),
    CountryDialCode(name: 'South Africa', iso2: 'ZA', dialCode: '27', flag: '🇿🇦'),
    CountryDialCode(name: 'Nigeria', iso2: 'NG', dialCode: '234', flag: '🇳🇬'),
    CountryDialCode(name: 'Indonesia', iso2: 'ID', dialCode: '62', flag: '🇮🇩'),
    CountryDialCode(name: 'Pakistan', iso2: 'PK', dialCode: '92', flag: '🇵🇰'),
    CountryDialCode(name: 'Russia', iso2: 'RU', dialCode: '7', flag: '🇷🇺'),
    CountryDialCode(name: 'China', iso2: 'CN', dialCode: '86', flag: '🇨🇳'),
  ];
}
