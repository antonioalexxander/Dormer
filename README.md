# Dormer

**Ejecuta programas de Windows en tu Mac, sin terminal.** · *Run Windows apps on your Mac, no terminal required.*

Dormer es una app nativa de macOS, libre y gratuita, que instala y abre programas de Windows usando [Wine](https://www.winehq.org). Cada programa vive en su propia **botella** (un entorno aislado).

> ⚠️ **Estado: Fase 3 (botellas y programas).** Dormer descarga Wine dentro de la app, crea botellas aisladas, ejecuta programas de Windows con su ícono real y permite exportar e importar botellas (probado con Notepad++). Aún faltan winetricks, gráficos DXMT/D3DMetal y lanzadores (Fase 4). Ver el [plan completo](docs/DESIGN.md#7-plan-por-fases).

Dormer no está afiliado a Microsoft ni a Apple. *Windows* es marca de Microsoft Corporation; *Mac* y *macOS* son marcas de Apple Inc.

## Requisitos

- macOS 14 o posterior, Mac con Apple Silicon
- Para compilar: Xcode 16 o posterior (probado con Xcode 27.2)

## Compilar

```sh
git clone <url-del-repo> dormer && cd dormer
make run      # compila y abre Dormer.app
make test     # pruebas unitarias
make integration NPP=~/Downloads/npp.8.9.9.1.Installer.x64.exe   # prueba real con Wine (descarga ~230 MB)
make lint     # swift-format + SwiftLint (opcional: brew install swiftlint)
```

También puedes abrir `Dormer.xcodeproj` en Xcode y pulsar ⌘R. Las vistas tienen SwiftUI Previews en modo claro y oscuro (abre cualquier archivo de `Packages/DormerKit/Sources/DormerUI/Views`).

## Estructura

| Ruta | Contenido |
|---|---|
| `App/` | Punto de entrada de la app, ícono |
| `Packages/DormerKit/Sources/DormerCore` | Modelos, parsers de logs, rutas, protocolos de servicios |
| `Packages/DormerKit/Sources/WineManager` | Catálogo de motores Wine (con SHA-256 fijados) y winetricks |
| `Packages/DormerKit/Sources/BottleManager` | Persistencia de botellas, detección de programas |
| `Packages/DormerKit/Sources/DormerUI` | Vistas SwiftUI, modelo de la app, datos de ejemplo |
| `docs/DESIGN.md` | Documento de diseño (arquitectura, riesgos, plan) |

## Licencia

[GPL-3.0-or-later](LICENSE). Wine, winetricks y DXMT (LGPL-2.1+) y DXVK (Zlib) se descargan y ejecutan como componentes independientes.

---

### English (short)

Dormer is a free, open-source native macOS app that installs and runs Windows programs through Wine, each in its own isolated *bottle*. **Phase 3 status:** Wine is downloaded and verified inside the app, bottles are isolated and can be exported/imported, Windows programs run with their real icons and settings (tested with Notepad++). Build with `make run`; test with `make test`. Licensed under GPL-3.0-or-later. A full English README arrives in Phase 5.
