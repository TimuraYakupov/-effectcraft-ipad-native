# Проверки RuPocket 0.1.0

Дата: 26 октября 2026 года.

## Успешная сборка

- Commit приложения: `c6844251fa1f3dd36ff2f5cdacfcb7b2df2d8b5d`.
- Ветка: `rupocket/iphone`.
- GitHub Actions: https://github.com/TimuraYakupov/-effectcraft-ipad-native/actions/runs/40338595885
- Runner: macOS 15 ARM64, Xcode 16.4.
- 10 из 10 DOM-проверок адаптера прошли.
- 5 из 5 XCTest прошли на симуляторе iPhone 16 Pro, iOS 18.5.
- Release-сборка ARM64 для настоящего iPhone: BUILD SUCCEEDED.
- Проверены структура IPA, Info.plist, идентификатор приложения, iPhone-only UIDeviceFamily, минимальная iOS 17.0 и Mach-O ARM64 executable.
- Включённые mobile.js и mobile.css побайтово совпадают с исходниками.
- SHA-256 IPA: `b60950edd6a134b4cda05c44bd75c6114784a1fc0bdfb6c0191092d08cb8dc90`.

## Практические ограничения

IPA неподписан. Для установки нужна подпись в настроенном Feather, SideStore или Xcode.

На настоящем iPhone не проверены вход на RuTracker, текущая вёрстка сайта, капча и скачивание реальной раздачи. Из среды подготовки прямое обращение к RuTracker возвращает Site Unavailable. Синтетические DOM-проверки не заменяют эти проверки.

Приложение сохраняет .torrent и передаёт magnet. Содержимое раздач не загружает.
