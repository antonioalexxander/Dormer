# Contribuir a Dormer · Contributing

¡Gracias por querer ayudar! *Thanks for helping.* Este documento está en español; al final hay un resumen en inglés.

## Antes de empezar

- Dormer es software libre bajo **GPL-3.0-or-later**. Al enviar una contribución aceptas que se publique bajo esa licencia.
- Todo lo que Dormer descarga o ejecuta debe ser **gratuito y de código abierto**, con la licencia verificada. No se aceptan cambios que:
  - incluyan o redistribuyan D3DMetal / Game Porting Toolkit u otro software con licencia restrictiva,
  - añadan cracks, saltos de licencia o de antitrampas,
  - añadan telemetría, cuentas o servicios en la nube obligatorios,
  - copien código, nombre, íconos o recursos gráficos de otras apps (Whisky incluida).
- Sé amable: lee el [Código de conducta](CODE_OF_CONDUCT.md).

## Preparar el entorno

Necesitas un Mac con Apple Silicon, macOS 14 o posterior y Xcode 16 o posterior (probado con Xcode 27.2).

```sh
make test          # pruebas unitarias (rápidas, sin red)
make build         # compila Dormer.app
make run           # compila y abre la app
make lint          # swift-format (obligatorio) y SwiftLint (si está instalado)
make format        # aplica swift-format
make integration NPP=/ruta/a/npp.Installer.x64.exe   # prueba real con Wine (descarga ~250 MB)
make probe INSTALLER=/ruta/a/setup.exe [ARGS='/S'] [VERBS='vcrun2022'] [PROGRAM=nombre]   # ¿funciona este programa?
make dmg           # compila en Release y crea build/Dormer-<versión>.dmg
```

`make probe` instala el programa en una botella desechable con los servicios reales, lo abre y cuenta qué pasó (y guarda una captura). Es la forma más rápida de preparar un informe de compatibilidad.

Para probar sin tocar tus botellas reales, define `DORMER_DATA_DIR` con una carpeta temporal.

## Cómo está organizado

Mira [docs/DESIGN.md](docs/DESIGN.md). En corto: `DormerCore` (modelos y parsers, sin dependencias), `WineManager` (motores, winetricks, gráficos), `BottleManager` (botellas, programas, lanzadores) y `DormerUI` (SwiftUI). La interfaz solo conoce **protocolos**; las implementaciones reales y las de ejemplo se inyectan.

## Tu primera contribución

1. Abre un *issue* o comenta uno existente antes de un cambio grande.
2. Crea una rama desde `main`.
3. Escribe pruebas. Los parsers que leen archivos de terceros (`.exe`, `.lnk`, `.aar`) deben tener pruebas con datos truncados o corruptos.
4. `make test` y `make lint` deben pasar.
5. Haz *commits* con [Conventional Commits](https://www.conventionalcommits.org/es/) (`feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`).
6. Actualiza `CHANGELOG.md` (sección *Unreleased*) si el cambio se nota.
7. Abre el *pull request* con la plantilla.

## Informes de compatibilidad

Lo más útil que puedes aportar es probar programas y contar el resultado con la plantilla «Informe de compatibilidad». Usa **Copiar para reporte** en la pestaña Registros: el texto ya quita tu nombre de usuario y tu carpeta personal. Cuenta también lo que **no** funciona: es información valiosa.

## Nuevos motores Wine o componentes

Se añaden en `Packages/DormerKit/Sources/WineManager/Resources/` (`runtimes.json`, `components.json`) con **URL HTTPS, tamaño y SHA-256 fijados** y su licencia. Comprueba la licencia y que la descarga sea gratuita; explica en el PR cómo verificaste ambas cosas.

## Traducciones

Los textos viven en `App/Localizable.xcstrings` (español es el idioma base). Para añadir un idioma, agrega sus traducciones en ese archivo con Xcode.

---

## English summary

Dormer is GPL-3.0-or-later. Only free and open-source tools are allowed; no redistribution of restrictively licensed software (D3DMetal/GPTK), no cracks or anti-cheat bypasses, no telemetry. Run `make test` and `make lint` before opening a PR, use Conventional Commits, add tests (including truncated/corrupted input for parsers), and update the changelog. Compatibility reports are the most helpful contribution — include failures too. New components need pinned HTTPS URL, size, SHA-256 and a verified license.
