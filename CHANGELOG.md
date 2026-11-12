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
  - DXMT (MIT, v0.80): descarga verificada (SHA-256) y una variante del motor Wine creada como clon APFS. Crea un dispositivo Direct3D 11 (nivel 11.0 frente al 9.3 de WineD3D), **pero con el Wine de Gcenx no puede dibujar en ventanas** (ver «Changed»), así que quedó desactivado.
  - Importación de D3DMetal desde el Game Porting Toolkit que aporta el usuario (imagen de disco o volumen montado): copia solo `D3DMetal.framework` y `libd3dshared.dylib`. Dormer nunca acepta la licencia de Apple por el usuario. **Importarlo no lo activa** (falta un motor Wine del Game Porting Toolkit).
  - Lanzadores `.app` en `~/Applications` con el ícono del programa; abren `dormer://run?…` (verificado de punta a punta con Notepad++).
  - Notificaciones locales cuando termina winetricks o un instalador, solo si Dormer está en segundo plano.
  - DXMT, DXVK y D3DMetal aparecen como «no disponibles» en el selector de backend en lugar de aceptar una elección que no funciona.
  - 29 pruebas nuevas; la prueba de extremo a extremo instala un verbo con winetricks y comprueba DXMT.

- Fase 5, calidad y publicación:
  - Español e inglés: catálogo de textos (`App/Localizable.xcstrings`, 325 entradas) y prueba que impide textos sin traducir o marcadores de formato rotos. Las alertas y mensajes de error ahora también se traducen.
  - Accesibilidad (revisión de código; sin prueba con VoiceOver real): nombres legibles en el selector de íconos, íconos decorativos ocultos, botón solo-hover fuera del árbol de accesibilidad (la acción ya existe en el programa) y animaciones que respetan «reducir movimiento».
  - Arranque medido: 0,4–0,5 s hasta mostrar la ventana (0,9 s en frío), con la app Release en esta máquina.
  - `make dmg` (compilación Release firmada ad hoc con *hardened runtime* y `.dmg` con suma SHA-256), flujo de publicación en GitHub (`release.yml`, solo con el `GITHUB_TOKEN`) y plantilla de cask de Homebrew. **El flujo y el cask no se han probado en GitHub/Homebrew.**
  - `make probe`: instala un programa en una botella desechable con los servicios reales y cuenta qué pasó; base de [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).
  - README en español e inglés, CONTRIBUTING, CODE_OF_CONDUCT, SECURITY, THIRD_PARTY_LICENSES y plantillas de issues y pull requests.

### Fixed
- Los programas .NET fallaban con «Wine Mono is not installed» en botellas aisladas (la configuración por defecto desde la Fase 3). Wine alcanza Mono, que viaja junto al motor, a través de la unidad Z:, y las botellas aisladas no la tienen. Ahora Dormer clona Mono dentro de la botella (`C:\windows\mono\mono-2.0`; en APFS es instantáneo) al crearla y, en las existentes, la próxima vez que se abre un programa. Se añadió a la prueba de extremo a extremo una aplicación .NET real.

### Changed
- **DXMT queda desactivado** con el motor Wine incluido: al probar Audacity 4 se vio que falla con *«your Wine has no exported symbols needed by DXMT»* (el `winemac.drv` de la compilación de Gcenx no expone lo que DXMT necesita para presentar imagen). La disponibilidad de DXMT ahora depende de una capacidad del motor (`dxmt`, `false` para los del catálogo). Mi verificación anterior solo comprobaba la creación del dispositivo, no el dibujo.
- «Acerca de» ya no dice que DXMT es LGPL (es MIT) ni lista DXVK.
- **Experimento DXMT (sin integrar en la app):** parche para `winemac.drv` de Wine 11.21 (`packaging/wine`) que añade la tabla `macdrv_functions`; con él DXMT v0.80 dibuja en ventanas (programa de prueba Direct3D 11 y Audacity 4.0.2). Sustituye al primer parche de solo exportar símbolos, que no bastaba. 
- **Imágenes de disco `.iso`:** Dormer monta la imagen en solo lectura, la muestra a la botella como unidad de CD (sin exponer el resto del Mac), arranca el instalador que indica `autorun.inf` (o `setup.exe`) y la expulsa cuando la botella queda inactiva. Si hay discos numerados en la misma carpeta (`CD1.iso`, `CD2.iso`…) se montan todos a la vez, cada uno como su unidad. Probado con imágenes propias de uno y de tres discos.
- **Discos ya montados:** si la imagen ya está montada (la montaste tú en Finder, quedó de una ejecución anterior o la usa otra botella), Dormer la reutiliza en vez de fallar con «Recurso ocupado». Solo expulsa los discos que montó él; el que montaste tú no se toca.
- **DXMT disponible como backend experimental** con Wine Staging 11.21: Dormer descarga el `winemac.so` parcheado (compilado en CI con `packaging/wine/build-winemac.sh`, fuentes con suma verificada), lo coloca en una copia del motor junto a DXMT y deja el motor original intacto. Probado con Audacity 4, Warzone 2100 y un programa propio (ventana, pantalla completa, Retina).
- La app usa los servicios reales; los datos de ejemplo quedan solo para las SwiftUI Previews.
- Los ajustes que aún no llegan a Wine (solo el backend gráfico: DXMT y D3DMetal) indican en qué fase se aplican.
- "Renombrar programa" pasa a "Editar programa".
- Eliminar una botella la mueve a la Papelera.
- Winetricks muestra la lista pero indica que la instalación llega en la Fase 4.
