# Dormer

**Ejecuta programas de Windows en tu Mac, sin terminal.** · [English](README.en.md)

Dormer es una app nativa de macOS, libre y gratuita, que instala y abre programas de Windows usando [Wine](https://www.winehq.org). Cada programa (o grupo de programas) vive en su propia **botella**: un entorno aislado con su propia «unidad C:». Sin cuentas, sin telemetría, sin suscripciones.

> **Estado: versión 0.1.0, en desarrollo inicial.** Funciona y está probada, pero todavía no hay versión publicada para descargar. Ver [limitaciones conocidas](#limitaciones-conocidas) y el [plan](docs/DESIGN.md#7-plan-por-fases).

## Antes de nada: qué es y qué no es

Wine **no es Windows**: reimplementa las funciones de Windows que los programas piden, y las que faltan fallan. Muchos programas clásicos funcionan; otros no (los que dependen de .NET Framework completo, WPF, WebView2, controladores del sistema o antitrampas, por ejemplo). Dormer hace que usar Wine sea fácil, pero no puede hacer que un programa funcione si Wine no sabe hacerlo. Mira la [tabla de compatibilidad](docs/COMPATIBILITY.md), que incluye lo que **no** funciona.

Si necesitas que *cualquier* programa de Windows funcione, lo que se parece a Windows es una máquina virtual con Windows para Apple Silicon (necesita licencia de Windows). Dormer no lo es.

## Qué hace

- **Todo desde la app, sin terminal:** descarga Wine (verificado con SHA-256), instala Rosetta si hace falta, crea botellas y ejecuta `.exe`, `.msi` y `.bat` (arrastrándolos o con ⌘R).
- **Botellas aisladas** (por defecto no ven el disco de tu Mac), que puedes duplicar, exportar a un archivo `.aar` e importar en otro Mac.
- **Programas con su ícono real**, detectados por los accesos directos que deja el instalador; anclables y con argumentos y variables propios.
- **Lanzadores `.app`** para abrir un programa con doble clic desde Finder o el Dock.
- **Componentes de Windows** (Visual C++, .NET, fuentes, DirectX…) con winetricks, desde una lista con búsqueda.
- **Ajustes por botella:** versión de Windows, escala (DPI), modo Retina, variables de entorno y backend gráfico (WineD3D, o DXMT como opción experimental para apps que piden Direct3D 11).
- **Registro de Wine en vivo,** con filtros, sugerencias automáticas (si falta una DLL, propone el componente) y «Copiar para reporte» sin tu nombre de usuario ni rutas personales.
- Español e inglés. Accesible con VoiceOver y teclado (revisión de código; falta una prueba con usuarios).

## Requisitos

- Mac con **Apple Silicon** y **macOS 14** o posterior.
- Los motores Wine gratuitos para Mac son para procesadores Intel, así que se ejecutan con **Rosetta 2** (Dormer te ayuda a instalarlo). Apple limitará Rosetta a partir de macOS 28.
- Unos 1,2 GB de disco para el motor Wine, más lo que ocupen tus programas. Internet solo para las descargas que tú inicias.

## Instalar

1. **Imagen de disco (`.dmg`):** cuando haya una versión publicada, descárgala de la página de *Releases*, abre el `.dmg` y arrastra Dormer a Aplicaciones. Su suma SHA-256 va junto al archivo.
2. **Homebrew:** existe una plantilla de cask en [packaging/homebrew](packaging/homebrew/dormer.rb) para un *tap* propio; aún no hay uno publicado.
3. **Desde el código fuente:** ver abajo.

> **Aviso de macOS (Gatekeeper):** Dormer es software libre y no está firmado con un ID de desarrollador de pago ni notarizado. La primera vez, macOS lo bloqueará: abre *Ajustes del Sistema › Privacidad y seguridad*, baja hasta el aviso sobre Dormer y elige **«Abrir de todos modos»**. (Desde macOS 15, el clic derecho › Abrir ya no basta.)

## Primeros pasos

1. Abre Dormer: el asistente comprueba Rosetta, descarga el motor Wine (~230 MB, una sola vez) y crea tu primera botella.
2. Arrastra un instalador `.exe` o `.msi` a la botella (o pulsa ⌘R). Dormer te avisa si el archivo viene de internet.
3. Cuando termine, el programa aparece en la lista: ábrelo con doble clic, ánclalo o crea un lanzador.
4. Si falla, mira la pestaña **Registros**: suele sugerirte qué componente instalar.

## Privacidad y seguridad

- **Sin telemetría ni cuentas.** Todo se guarda en `~/Library/Application Support/Dormer/` (y los lanzadores que crees).
- Las descargas (Wine, winetricks, DXMT y su controlador) son por HTTPS y se comprueban contra un tamaño y un SHA-256 fijados en el código.
- Los archivos de botella `.aar` se validan antes de extraerse.
- Wine **no es un sandbox de seguridad**: un programa malicioso dentro de una botella puede dañar lo que la botella alcance. No ejecutes software en el que no confíes. Más en [SECURITY.md](SECURITY.md).

## Limitaciones conocidas

- **No todo funciona.** Probado y documentado en [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).
- **Power BI Desktop:** el instalador falla dentro de Wine; no esperes que funcione.
- **Notepad++:** la barra de menú se ve apilada en filas (problema de Wine con esa app); se puede usar.
- **Apps modernas que piden Direct3D 11 real** (por ejemplo Audacity 4) no abren con WineD3D (solo ofrece el nivel 9.3 en este Mac). Con el backend **DXMT (experimental)** sí se dibujan (probado con Audacity 4 y Warzone 2100); usa un [controlador de Wine parcheado](packaging/wine/README.md) que Dormer descarga. Pocos programas probados y ningún juego comercial.
- **D3DMetal (Game Porting Toolkit):** puedes importarlo, pero todavía no se puede usar (necesita un motor Wine del Game Porting Toolkit que Dormer no incluye). DXVK no se ofrece (sin versiones desde 2024).
- **Wine Gecko** (motor web de Windows) sin verificar en botellas aisladas.
- Compilación del `.dmg` y publicación automática (CI): escritas pero **sin probar** en GitHub todavía.

## Compilar y probar

Necesitas Xcode 16 o posterior (probado con Xcode 27.2).

```sh
git clone <url-del-repo> dormer && cd dormer
make run        # compila y abre Dormer.app
make test       # pruebas unitarias (sin red)
make lint       # swift-format (y SwiftLint si lo tienes: brew install swiftlint)
make dmg        # compila en Release y crea build/Dormer-<versión>.dmg
make integration NPP=~/Downloads/npp.8.9.9.1.Installer.x64.exe   # prueba real con Wine (~250 MB)
make probe INSTALLER=~/Downloads/setup.exe VERBS=vcrun2022 PROGRAM=nombre   # ¿funciona este programa?
```

También puedes abrir `Dormer.xcodeproj` y pulsar ⌘R. Con `DORMER_DATA_DIR=/carpeta` los datos de prueba no tocan tus botellas.

| Ruta | Contenido |
|---|---|
| `App/` | Punto de entrada, ícono, catálogo de textos (`Localizable.xcstrings`) |
| `Packages/DormerKit/Sources/DormerCore` | Modelos, parsers (PE, acceso directo), rutas, protocolos |
| `Packages/DormerKit/Sources/WineManager` | Motores Wine, winetricks, DXMT/GPTK, ejecución |
| `Packages/DormerKit/Sources/BottleManager` | Botellas, programas, íconos, lanzadores, exportar/importar |
| `Packages/DormerKit/Sources/DormerUI` | Vistas SwiftUI y modelo de la app |
| `docs/` | [Diseño](docs/DESIGN.md) y [compatibilidad](docs/COMPATIBILITY.md) |

## Contribuir

Lee [CONTRIBUTING.md](CONTRIBUTING.md) y el [Código de conducta](CODE_OF_CONDUCT.md). Lo más útil: probar programas y contar el resultado, también cuando falla.

## Licencia

[GPL-3.0-or-later](LICENSE). Wine, winetricks y DXMT se descargan y ejecutan como componentes independientes con sus propias licencias; ver [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md). Dormer no incluye ni redistribuye D3DMetal / Game Porting Toolkit.

Dormer no está afiliado a Microsoft ni a Apple. *Windows* es marca de Microsoft Corporation; *Mac* y *macOS* son marcas de Apple Inc.
