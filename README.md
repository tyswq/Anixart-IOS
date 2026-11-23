<div align="center">

# Anix для iOS

Неофициальный клиент **Anixart** для iPhone на SwiftUI с дизайном **Liquid Glass**.

[![Сборка](https://github.com/tyswq/Anixart-IOS/actions/workflows/build.yml/badge.svg)](https://github.com/tyswq/Anixart-IOS/actions/workflows/build.yml)
[![Релиз](https://img.shields.io/github/v/release/tyswq/Anixart-IOS?style=flat-square&color=ef4f5c)](https://github.com/tyswq/Anixart-IOS/releases/latest)
[![Лицензия](https://img.shields.io/github/license/tyswq/Anixart-IOS?style=flat-square&color=22c55e)](LICENSE)
![iOS 18+](https://img.shields.io/badge/iOS-18%2B-black?style=flat-square)

[Скачать](https://github.com/tyswq/Anixart-IOS/releases/latest) ·
[История изменений](CHANGELOG.md) ·
[Сообщить об ошибке](https://github.com/tyswq/Anixart-IOS/issues/new/choose)

</div>

Клиент основан на проекте [arigandores/anix](https://github.com/arigandores/anix): те же эндпоинты, подпись
запросов и парсеры видео. С разработчиками Anixart не связан и ими не одобрен.

## Установка

Приложение не подписано, поэтому ставится через sideloading. Компьютер с Windows или Mac нужен только для установки.

1. Скачайте `Anix-<версия>.ipa` со страницы [Releases](https://github.com/tyswq/Anixart-IOS/releases/latest).
2. Установите [Sideloadly](https://sideloadly.io). На Windows нужны iTunes и iCloud, скачанные с сайта Apple, а не из Microsoft Store.
3. Подключите iPhone кабелем и разрешите доверие компьютеру.
4. Перетащите `.ipa` в окно Sideloadly, введите свой Apple ID и нажмите **Start**.
5. Включите режим разработчика: **Настройки → Конфиденциальность и безопасность → Режим разработчика**, затем перезагрузите iPhone.
6. Доверьте профиль: **Настройки → Основные → VPN и управление устройством** → ваш Apple ID → **Доверять**.

Обновление: установите новый `.ipa` поверх старого тем же способом, вход и данные сохранятся.

> Бесплатный Apple ID подписывает приложение на **7 дней**, потом его нужно переустановить. Автоматически продлевают подпись
> [AltStore](https://altstore.io) и [SideStore](https://sidestore.io). Подпись на год даёт платный аккаунт разработчика.

Минимальная система — iOS 18. На iOS 26 интерфейс использует Liquid Glass, на iOS 18–25 вместо него матовый материал.

## Сборка своими руками

```sh
brew install xcodegen
xcodegen generate
open Anix.xcodeproj
```

Выберите свою команду подписи и запустите. Нужен Xcode 26.

## Структура проекта

```
Anix/
  AnixApp.swift         точка входа, корневой экран и вкладки
  Core/                 API, модели, подпись запросов, вход, настройки, хранилища
  UI/                   экраны: главная, релиз, поиск, закладки, профиль, комментарии, настройки
  Player/               плеер на AVPlayer и разбор видеоисточников
  Resources/en.lproj/   английская локализация (ключи — русские исходные строки)
  Assets.xcassets/      иконка и ресурсы
project.yml             описание проекта для XcodeGen
CHANGELOG.md            история изменений
```

Проект генерируется XcodeGen, файла `.xcodeproj` в репозитории нет.

## Частые вопросы

**Не загружаются обложки.** Включите **Настройки → Альтернативное соединение**. Картинки пойдут через зеркало,
это помогает, когда провайдер блокирует часть адресов CDN.

**Приложение перестало открываться.** Прошла неделя, и подпись бесплатного Apple ID истекла. Переустановите `.ipa`.

**Не работает видео из какого-то источника.** Прямое воспроизведение есть у Kodik и AniLibria. Остальные источники
открываются во встроенном веб-плеере, и его работа зависит от самого источника.

**На английском часть текста осталась русской.** Описание релиза, жанры и статус переводятся встроенным переводчиком iOS.
При первом запуске система может предложить скачать языковой пакет. Комментарии и названия серий не переводятся.

## Лицензия

Код распространяется по лицензии [MIT](LICENSE), как и оригинальный проект.
Anixart, его название, логотип и контент принадлежат правообладателям. Каталог, аккаунты и комментарии предоставляет
сервис Anixart, видео — сторонние источники.
