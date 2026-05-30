# FPV STRIKE — iOS (Swift + SceneKit 3D)

**3D FPV-дрон игра от первого лица**: управляй дроном, взрывай танки бомбами, уворачивайся от снарядов.

## Особенности
- 🎮 **Вид от первого лица** — настоящий FPV с камеры дрона
- 🎨 **3D модели** — процедурные танки, взрывы, эффекты
- 💥 **Физика и взрывы** — реалистичные взрывы с радиусом поражения
- 📺 **FPV-стиль** — scanlines, мерцание, виньетка, неон-HUD
- 📱 **Тач-управление** — виртуальный джойстик + кнопка бомбы

## Структура
```
ios/
├── DroneFPV.xcodeproj      # проект Xcode (objectVersion 77, Xcode 16+)
└── DroneFPV/
    ├── DroneFPVApp.swift    # SwiftUI + HUD + управление
    └── GameScene3D.swift    # 3D игра (SceneKit)
```
- Bundle ID: `com.fpv.dronefpv` (можно поменять в настройках таргета)
- iOS 16+, портрет, без сторонних зависимостей и ассетов
- Все модели процедурные (танки, взрывы, эффекты)

## Управление
- **Левая половина экрана** — виртуальный джойстик (движение дрона)
- **Кнопка BOMB (справа внизу)** — сброс бомбы (есть перезарядка)
- **Тап на стартовом/финальном экране** — старт / рестарт
- Красный круг на земле — точка падения бомбы (с упреждением по скорости)

## Геймплей
- Волны танков (каждая волна сложнее)
- Танки стреляют снарядами по дрону
- HP-бары у танков (с 3-й волны)
- 4 жизни, неуязвимость после попадания
- Счёт за уничтожение танков и прохождение волн

## Сборка unsigned .ipa (для Sideloadly)
На Mac / облачном Mac с Xcode:

```bash
cd ios

# 1) собрать без подписи
xcodebuild -project DroneFPV.xcodeproj -scheme DroneFPV \
  -configuration Release -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  clean build

# 2) упаковать .app в .ipa
cd build/Build/Products/Release-iphoneos
mkdir -p Payload
cp -R DroneFPV.app Payload/
zip -r DroneFPV.ipa Payload
```
Получишь `DroneFPV.ipa` — его и скармливаешь Sideloadly.

> Если собираешь прямо в Xcode (GUI): открой `DroneFPV.xcodeproj`,
> выбери Any iOS Device → Product ▸ Archive, либо просто запусти на
> своём айфоне через свой Apple ID.

## GitHub Actions (автосборка)
Репозиторий содержит `.github/workflows/build.yml` — при пуше в `main` или ручном запуске (workflow_dispatch) автоматически собирается unsigned .ipa на macOS-раннере и загружается в артефакты.

**Как скачать:**
1. Зайди в **Actions** → последний успешный run
2. Скачай артефакт `DroneFPV-unsigned-ipa`
3. Распакуй → получишь `DroneFPV.ipa`

## Установка через Sideloadly
1. Поставь Sideloadly (Win/Mac) + Apple Mobile Device Support / iTunes (Win).
2. Подключи айфон кабелем, доверься компьютеру.
3. Перетащи `DroneFPV.ipa` в Sideloadly, введи свой Apple ID.
4. Start → приложение установится.
5. На айфоне: **Настройки ▸ Основные ▸ VPN и управление устройством** →
   доверь своему профилю разработчика.
6. Запускай.

> Бесплатный Apple ID = подпись живёт **7 дней**, потом переподписать
> тем же Sideloadly. Платный Developer ($99) = 1 год.

## Настройка под себя
В `GameScene3D.swift`, блок `// MARK: - Tunables`:
- `droneSpeed` — скорость дрона
- `droneHeight` — высота камеры (FPV)
- `bombReload` / `bombBlast` — перезарядка и радиус бомбы
- `shellSpeed` — скорость снарядов танков
- `neon` — цвет HUD
- `fieldHalf` — размер поля (половина стороны)

## Технические детали
- **SceneKit** — 3D-движок Apple (Metal под капотом)
- **Процедурные модели** — танки собираются из примитивов (box, cylinder, torus)
- **Камера** — SCNCamera с FOV 75°, наклон 30° вниз
- **Освещение** — ambient + directional с тенями
- **Эффекты** — SwiftUI Canvas для scanlines, RadialGradient для виньетки
- **Управление** — DragGesture для джойстика, CADisplayLink для update loop

## Производительность
- 60 FPS на iPhone 12+ (Metal)
- ~30-40 FPS на iPhone X/XS
- Оптимизация: процедурные модели (без текстур), простые шейдеры, culling за границами поля

## Лицензия
MIT — делай что хочешь.
