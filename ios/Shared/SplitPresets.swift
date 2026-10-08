import Foundation

// Готовые наборы для раздельного туннелирования.
// Записи того же формата, что и пользовательский ввод: домены, IPv4/IPv6 адреса и CIDR.
//
// Источники:
// - Telegram: подсети из официального списка Telegram (core.telegram.org/resources/cidr.txt),
//   перенесены при добавлении функции. Список меняется, сверять перед релизом.
// - Российские сервисы, YouTube и Google Video: списки доменов из задания; домены резолвятся в IP при подключении.
// - Локальная сеть: стандартные частные и link-local диапазоны RFC 1918, RFC 3927, RFC 4193, RFC 4291.

enum SplitPresets {
    static func entries(for preset: SplitPreset) -> [String] {
        switch preset {
        case .telegram:
            return telegram
        case .youtube:
            return youtube
        case .russianServices:
            return russianServices
        case .localNetwork:
            return localNetwork
        }
    }

    static func title(for preset: SplitPreset) -> String {
        switch preset {
        case .telegram:
            return "Telegram"
        case .youtube:
            return "YouTube и Google Video"
        case .russianServices:
            return "Российские сервисы"
        case .localNetwork:
            return "Локальная сеть"
        }
    }

    /// Короткое пояснение под переключателем.
    static func subtitle(for preset: SplitPreset) -> String {
        switch preset {
        case .telegram:
            return "Подсети Telegram и домены t.me, telegram.org. Обычно идут через VPN."
        case .youtube:
            return "YouTube и видео-серверы Google. Домены резолвятся, поэтому часть CDN-адресов может не попасть."
        case .russianServices:
            return "Яндекс, VK, Почта Mail.ru, банки и госсервисы. Удобно исключить из VPN."
        case .localNetwork:
            return "Адреса роутера, принтеров и других устройств рядом. Обычно исключают из VPN."
        }
    }

    static let telegram: [String] = [
        "91.108.4.0/22",
        "91.108.8.0/22",
        "91.108.12.0/22",
        "91.108.16.0/22",
        "91.108.20.0/22",
        "91.108.56.0/22",
        "95.161.64.0/20",
        "149.154.160.0/20",
        "185.76.151.0/24",
        "2001:67c:4e8::/48",
        "2001:b28:f23c::/48",
        "2001:b28:f23d::/48",
        "2001:b28:f23f::/48",
        "2a0a:f280::/32",
        "telegram.org",
        "t.me",
        "telegram.me",
        "telesco.pe",
        "tdesktop.com"
    ]

    static let youtube: [String] = [
        "youtube.com",
        "googlevideo.com",
        "ytimg.com",
        "ggpht.com",
        "youtu.be",
        "youtube-nocookie.com",
        "googleapis.com"
    ]

    static let russianServices: [String] = [
        "yandex.ru",
        "ya.ru",
        "yandex.net",
        "vk.com",
        "vk.ru",
        "userapi.com",
        "mail.ru",
        "gosuslugi.ru",
        "sberbank.ru",
        "tinkoff.ru",
        "tbank.ru",
        "ozon.ru",
        "wildberries.ru",
        "avito.ru",
        "kinopoisk.ru",
        "rutube.ru",
        "mos.ru",
        "nalog.ru",
        "2gis.ru"
    ]

    static let localNetwork: [String] = [
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16",
        "169.254.0.0/16",
        "fc00::/7",
        "fe80::/10"
    ]
}
