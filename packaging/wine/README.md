# Wine con DXMT: lo que falta y el plan

**Problema (verificado):** el Wine de Gcenx 11.21 que usa Dormer oculta cinco símbolos de `winemac.so` que DXMT busca con `dlsym`; sin ellos DXMT crea el dispositivo Direct3D 11 pero falla al dibujar en una ventana (`your Wine has no exported symbols needed by DXMT`). Apps como Audacity 4 se quedan por eso en «Failed to initialize graphics backend for D3D11».

**Arreglo mínimo:** [0001-winemac-export-metal-view-symbols.patch](0001-winemac-export-metal-view-symbols.patch) (5 líneas, solo visibilidad de símbolos), aplicado a `winemac.drv` de Wine 11.21.

## Pasos para reconstruir solo `winemac.so`

No está automatizado ni se ha ejecutado todavía: requiere ejecutar un `configure` y un compilador cruzado descargados, y lo debe aprobar quien mantiene el proyecto.

1. Fuente oficial: `https://dl.winehq.org/wine/source/11.x/wine-11.21.tar.xz` (verificar su suma en la página de WineHQ).
2. Herramientas de compilación (en una carpeta aparte, sin instalar nada en el sistema): GNU bison ≥ 3 (el de macOS es 2.3) y `llvm-mingw` (Wine 11 exige un compilador cruzado de Windows en macOS).
3. `patch -p1 < 0001-…patch`, luego `arch -x86_64 ./configure --enable-win64 --disable-tests` (+ `--without-…` para dependencias no necesarias) y `make dlls/winemac.drv/winemac.so`.
4. Reemplazar `lib/wine/x86_64-unix/winemac.so` en una **copia** del motor (Dormer ya sabe crear variantes como clon APFS) y marcar la capacidad `dxmt` de ese motor.
5. Verificar con una app real (Audacity 4), no solo con la creación del dispositivo.

Riesgo conocido: el `winemac.drv` (PE) de Gcenx y el `winemac.so` propio deben coincidir en el ABI de llamadas Unix; con la misma versión 11.21 debería, pero se comprueba empíricamente.

## Para Wine (upstream)

Lo que sí se puede ofrecer a WineHQ, sin pretender que lo acepten tal cual:

- **Parche pequeño** (este): exportar esos símbolos. Es el mismo en espíritu que lo que CrossOver hace con su tabla `macdrv_functions`.
- **Propuesta mejor:** una interfaz documentada en `winemac.drv` para que una capa externa obtenga un `CAMetalLayer` a partir de un `HWND` (como `winevulkan` hace con Vulkan), en lugar de depender de símbolos internos. Es una conversación de diseño con los mantenedores de `winemac.drv`.
- Envío: lista `wine-devel` o *merge request* en `gitlab.winehq.org`, con cuenta propia de quien envía y siguiendo su guía de contribución. **Dormer no puede enviarlo por ti.**
