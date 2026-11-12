# Changelog

Todos los cambios relevantes de este proyecto se documentan aquí.
El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [versionado semántico](https://semver.org/lang/es/).

## [Unreleased]

### Added
- Documento de diseño (Fase 0): arquitectura, wireframes, riesgos y plan por fases.
- Fase 1, interfaz con datos de ejemplo:
  - Ventana principal con barra lateral de botellas y pestañas Programas, Configuración y Registros.
  - Cuadrícula de programas anclados, lista de ejecutables detectados y zona de arrastrar y soltar.
  - Configuración por botella: versión de Windows, backend gráfico, Retina, DPI, sincronización, aislamiento y variables de entorno.
  - Visor de registros con filtros, sugerencias automáticas (DLL faltantes), exportación y "Copiar para reporte" sin datos personales.
  - Bienvenida en 3 pasos, hoja de winetricks, confirmación antes de ejecutar archivos descargados y ajustes de la app.
  - Atajos: ⌘N, ⌘R, ⌘1/2/3, ⇧⌘C, ⇧⌘W, ⌘., ⌘,.
  - Ícono original generado con `Tools/make-icon.swift`.
- Paquete `DormerKit` con los módulos DormerCore, WineManager, BottleManager y DormerUI, con pruebas unitarias.
- Catálogo de motores Wine con SHA-256 fijados (Gcenx 11.21, staging y devel).
- Configuración de swift-format y SwiftLint, Makefile y CI en GitHub Actions.
- Fase 2, Wine real:
  - Descarga de Wine dentro de la app (HTTPS), con progreso, verificación de tamaño y SHA-256 fijado, descompresión e instalación atómica en `~/Library/Application Support/Dormer/Runtimes`. Comprueba que Wine arranca antes de darlo por instalado.
  - Detección e instalación de Rosetta 2 con el instalador de Apple.
  - Creación de botellas reales (`wineboot`, versión de Windows con `winecfg`); aparecen en la barra lateral mientras se crean.
  - Ejecución de `.exe`, `.msi` (`msiexec`) y `.bat` (`cmd`) y de programas anclados con argumentos; salida de Wine en vivo en Registros.
  - Detección de programas instalados en `Program Files` y `AppData\Local\Programs`.
  - "Detener todo" con `wineserver -k`; abrir la unidad C:, mostrar programas en Finder y abrir la carpeta de datos.
  - Duplicar botellas (copia APFS) y eliminarlas moviéndolas a la Papelera.
  - Variables de entorno por botella y por programa; Wine no hereda el entorno de Dormer.
  - Prueba de extremo a extremo (`make integration`) que instala y abre Notepad++.

### Changed
- La app usa los servicios reales; los datos de ejemplo quedan solo para las SwiftUI Previews.
- Ajustes que aún no llegan a Wine (Retina, DPI, backend gráfico, unidad Z:, cambiar la versión de Windows) muestran en qué fase se aplican.
- Winetricks muestra la lista pero indica que la instalación llega en la Fase 4.
