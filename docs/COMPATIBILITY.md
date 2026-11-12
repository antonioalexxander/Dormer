# Compatibilidad · Compatibility

Lo que se ha **probado de verdad** en Dormer, incluido lo que **no** funciona. Cada fila indica qué se comprobó y qué no. Si pruebas algo, cuéntalo con la plantilla «Informe de compatibilidad» (ver [CONTRIBUTING.md](../CONTRIBUTING.md)); `make probe` hace gran parte del trabajo.

**Entorno de las pruebas:** MacBook Air Apple M5 · macOS 27.2.1 · Dormer 0.1.0 · Wine Staging 11.21 (compilación de Gcenx, con Rosetta 2) · Windows 10 simulado · botella aislada (sin unidad Z:) · Direct3D de Wine (WineD3D).

## Programas

| Programa | Versión | Resultado | Qué se comprobó y notas |
|---|---|---|---|
| **Notepad++** | 8.9.9.1 (x64) | ✅ Funciona, con un defecto visual | Instalador silencioso (`/S`) sin errores; Dormer detecta el programa por su acceso directo («Notepad++») con su ícono real; se abre su ventana. **Defecto:** la barra de menú se ve apilada en varias filas (con Windows 7 y 10; problema de Wine con esta app). No se probó un uso prolongado ni todas sus funciones. |
| **Bloc de notas de 32 bits** (el de Wine) | 11.21 | ✅ Funciona | Comprueba que los programas de 32 bits arrancan (modo WoW64). |
| **Programa .NET** (el compilador de C# que viene con Wine Mono) | Mono 11.3.0 | ✅ Funciona | Se ejecuta en una botella aislada. *(Antes de la corrección `44f9897` fallaba con «Wine Mono is not installed».)* |
| **Audacity** | 4.0.2 (x86_64, `.msi`) | ❌ No funciona | El `.msi` se instala sin errores (con `vcrun2022`) y Dormer lo detecta, pero al abrirlo muestra *«Failed to initialize graphics backend for D3D11»*: Audacity 4 usa Qt 6, que pide un Direct3D 11 real y WineD3D solo ofrece el nivel 9.3 en este Mac. Con DXMT tampoco: falla con *«your Wine has no exported symbols needed by DXMT»*. Con `QT_QUICK_BACKEND=software` ni siquiera aparece una ventana. |
| **Power BI Desktop** | `PBIDesktopSetup_x64` | ❌ No funciona | El instalador se cae por dentro con `Unhandled page fault`, también en modo silencioso. Causa probable (sin confirmar): depende de componentes de Windows que Wine Mono no ofrece (.NET Framework completo, WPF). |

> La prueba con una aplicación «mediana» (Audacity 4) dio un resultado **negativo**. Es un resultado útil: Dormer no pretende que todo funcione. Las apps modernas basadas en Qt 6/Direct3D 11, .NET Framework completo, WPF o WebView2 son candidatas a fallar con el motor Wine actual.

## Componentes de Windows (winetricks)

Instalados y comprobados (los archivos esperados quedaron en la botella, 32 y 64 bits cuando corresponde): `corefonts`, `d3dcompiler_47`, `vcrun2022`, `d3dx9`. **No se comprobó** que cada uno arregle un programa concreto.

La lista curada tiene otros verbos (`dotnet48`, `dotnet40`, `xact`, `msxml6`…) que **no se han probado** en Dormer.

## Gráficos

| Backend | Estado | Notas |
|---|---|---|
| **WineD3D** (el de Wine) | ✅ Disponible | En este Mac ofrece Direct3D 11 con nivel de características 9.3 (a través de OpenGL). Suficiente para programas de oficina; insuficiente para programas que exigen Direct3D 11 real. |
| **DXMT** (v0.80, MIT) | ❌ No disponible | Crea el dispositivo Direct3D 11 (nivel 11.0) pero **no puede dibujar en ventanas** con el Wine de Gcenx: a su `winemac.drv` le faltan símbolos que DXMT necesita. Se activará cuando el catálogo incluya un motor Wine compatible (el catálogo ya tiene la capacidad `dxmt`, que hoy es `false`). |
| **DXVK-macOS** | ❌ No ofrecido | Sin versiones desde 2024. |
| **D3DMetal** (Game Porting Toolkit) | ❌ No disponible | Puedes importarlo desde tu copia del GPTK, pero necesita un motor Wine del GPTK que Dormer no incluye. No verificado. |

## Cómo se prueba

```sh
make probe INSTALLER=~/Downloads/setup.exe VERBS=vcrun2022 PROGRAM=nombre
```

Crea una botella desechable con Wine real, instala el programa (silencioso), lo detecta, lo abre, espera una ventana y guarda una captura. Para `.msi` usa `msiexec /i … /qn` automáticamente; para otros instaladores pasa `ARGS='/S'` (o el interruptor silencioso que use). Cuenta lo que viste, también si falla.
