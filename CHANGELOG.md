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
- Fase 3, botellas y programas:
  - Íconos reales de los programas, leídos de sus `.exe` con un parser PE propio (con caché en disco).
  - Descubrimiento de programas por los accesos directos del Menú Inicio (nombre y argumentos que puso el instalador), además del escaneo de `Program Files`.
  - Ajustes aplicados de verdad al abrir un programa: versión de Windows, escala (DPI), modo Retina y aislamiento de archivos.
  - Aislamiento: sin la unidad Z: ni los enlaces a Escritorio, Documentos y demás carpetas del Mac. Los archivos que abres desde el Mac se clonan a `C:\Dormer\Incoming` (instantáneo en APFS) y se borran a las 24 h.
  - Exportar e importar botellas como archivo `.aar` (Apple Archive), validando el archivo antes de extraerlo: rechaza rutas con `..`, rutas absolutas, enlaces que apuntan fuera y tipos de archivo raros.
  - Editar programas anclados: nombre, argumentos y variables de entorno propias.
  - Botones de winecfg y del editor del registro.
  - Dormer se niega a duplicar o exportar una botella con programas abiertos, para no copiar un registro a medias.
  - Pruebas: 43 nuevas, incluidas pruebas con archivos truncados y corruptos para los parsers.

- Fase 4, extras del MVP:
  - Winetricks real: Dormer descarga el script oficial fijado (versión 20260125, SHA-256 verificado) y lo ejecuta en la botella; la hoja muestra el avance, la salida en vivo, qué componentes ya están instalados y permite cancelar. Verificado instalando `corefonts`, `d3dcompiler_47`, `vcrun2022` y `d3dx9` (con sus versiones de 32 y 64 bits).
  - `cabextract` sin compilar nada: un pequeño asistente propio sobre el `bsdtar` de macOS (que lee archivos CAB, incluidos los instaladores autoextraíbles de Microsoft) cubre las opciones que usa winetricks. No hace falta alojar binarios.
  - DXMT (MIT, v0.80) como backend gráfico experimental: descarga verificada (SHA-256) y una variante del motor Wine creada como clon APFS, para que solo las botellas que lo elijan lo usen. Verificado con la creación de un dispositivo Direct3D 11: WineD3D da nivel 9.3 y DXMT nivel 11.0. **No se probó con juegos.**
  - Importación de D3DMetal desde el Game Porting Toolkit que aporta el usuario (imagen de disco o volumen montado): copia solo `D3DMetal.framework` y `libd3dshared.dylib`. Dormer nunca acepta la licencia de Apple por el usuario. **Importarlo no lo activa** (falta un motor Wine del Game Porting Toolkit).
  - Lanzadores `.app` en `~/Applications` con el ícono del programa; abren `dormer://run?…` (verificado de punta a punta con Notepad++).
  - Notificaciones locales cuando termina winetricks o un instalador, solo si Dormer está en segundo plano.
  - DXVK y D3DMetal aparecen como «no disponibles» en el selector de backend en lugar de aceptar una elección que no funciona.
  - 29 pruebas nuevas; la prueba de extremo a extremo instala un verbo con winetricks y comprueba DXMT.

### Fixed
- Los programas .NET fallaban con «Wine Mono is not installed» en botellas aisladas (la configuración por defecto desde la Fase 3). Wine alcanza Mono, que viaja junto al motor, a través de la unidad Z:, y las botellas aisladas no la tienen. Ahora Dormer clona Mono dentro de la botella (`C:\windows\mono\mono-2.0`; en APFS es instantáneo) al crearla y, en las existentes, la próxima vez que se abre un programa. Se añadió a la prueba de extremo a extremo una aplicación .NET real.

### Changed
- La app usa los servicios reales; los datos de ejemplo quedan solo para las SwiftUI Previews.
- Los ajustes que aún no llegan a Wine (solo el backend gráfico: DXMT y D3DMetal) indican en qué fase se aplican.
- "Renombrar programa" pasa a "Editar programa".
- Eliminar una botella la mueve a la Papelera.
- Winetricks muestra la lista pero indica que la instalación llega en la Fase 4.
