# FPV STRIKE - iOS

3D FPV-игра на SwiftUI и SceneKit: управляй дроном, бей танки бомбами, уходи от снарядов и проходи всё более плотные волны.

## Что внутри

- FPV-камера от дрона с HUD, сканлайнами, вспышками попаданий и лёгкой тряской.
- Процедурная 3D-сцена без внешних ассетов: поле, сетка, границы, укрытия, антенны, камни, танки, снаряды и взрывы.
- Сенсорное управление: левая половина экрана - виртуальный джойстик, справа - кнопка сброса бомбы.
- Игровой цикл с волнами, растущей сложностью, HP у танков, перезарядкой бомбы, жизнями, паузой и локальным рекордом.
- GitHub Actions собирает unsigned `.ipa`, который можно установить через Sideloadly или похожий инструмент.

## Структура

```text
ios/
├── DroneFPV.xcodeproj
├── DroneFPV/
│   ├── DroneFPVApp.swift    # SwiftUI, HUD, меню, управление, состояние
│   └── GameScene3D.swift    # SceneKit-сцена, волны, физика, эффекты
├── .github/workflows/
│   └── build-ios.yml        # сборка unsigned IPA
└── exportOptions.plist
```

## Требования

- Xcode 16+
- iOS 16+
- Bundle ID: `com.fpv.dronefpv`
- Ориентация: landscape
- Сторонние зависимости не используются

## Локальная сборка unsigned IPA

На Mac с Xcode:

```bash
cd ios

xcodebuild clean build \
  -project DroneFPV.xcodeproj \
  -scheme DroneFPV \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

cd build/Build/Products/Release-iphoneos
mkdir -p Payload
cp -R DroneFPV.app Payload/
zip -qry DroneFPV.ipa Payload
```

Готовый файл будет здесь:

```text
build/Build/Products/Release-iphoneos/DroneFPV.ipa
```

## Автосборка на GitHub

Workflow `.github/workflows/build-ios.yml` запускается при push в `main`, pull request и вручную через `workflow_dispatch`.

Как скачать IPA:

1. Открой вкладку `Actions`.
2. Выбери последний успешный запуск `Build iOS App`.
3. Скачай artifact `DroneFPV-unsigned-ipa`.
4. Распакуй архив и установи `DroneFPV.ipa`.

## Установка через Sideloadly

1. Установи Sideloadly и Apple Mobile Device Support / iTunes.
2. Подключи iPhone кабелем и доверься компьютеру на устройстве.
3. Перетащи `DroneFPV.ipa` в Sideloadly.
4. Введи Apple ID и нажми Start.
5. На iPhone открой `Настройки -> Основные -> VPN и управление устройством` и доверься профилю разработчика.

Бесплатная подпись Apple ID обычно действует 7 дней. После этого приложение нужно переподписать.

## Настройка баланса

Основные параметры находятся в `DroneFPV/GameScene3D.swift`:

- `droneSpeed` - скорость дрона.
- `droneHeight` - высота FPV-камеры.
- `bombReload`, `bombFuse`, `bombBlast` - перезарядка, задержка и радиус бомбы.
- `shellSpeed` - скорость снарядов танков.
- `fieldHalf` - половина размера боевого поля.

## Лицензия

MIT. Делай с проектом что хочешь.
