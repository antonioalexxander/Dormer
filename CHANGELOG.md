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
