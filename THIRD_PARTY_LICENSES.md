# Licencias de terceros · Third-party licenses

Dormer es GPL-3.0-or-later (ver [LICENSE](LICENSE)). Usa los programas siguientes **como procesos o archivos independientes**: no se enlazan con Dormer. La mayoría se descarga cuando hace falta, desde su fuente, con suma SHA-256 verificada; el código fuente de cada uno está en el enlace indicado.

| Componente | Licencia | Cómo lo usa Dormer | Fuente |
|---|---|---|---|
| **Wine** y parches de **Wine Staging** | LGPL-2.1-o-posterior | Se descarga como compilación de Gcenx y se ejecuta como proceso | https://gitlab.winehq.org/wine/wine · https://github.com/wine-staging/wine-staging |
| **Compilaciones macOS de Wine (Gcenx)** | Licencias de sus componentes (Wine LGPL-2.1+, MoltenVK Apache-2.0, GStreamer LGPL-2.1+, SDL2 zlib, …) | Archivo descargado por el usuario desde GitHub | https://github.com/Gcenx/macOS_Wine_builds |
| **Wine Mono** y **Wine Gecko** | Varias licencias libres (MIT, MPL-2.0, LGPL…) según el componente; ver su repositorio | Vienen dentro del motor Wine descargado; Dormer clona Mono dentro de las botellas aisladas | https://gitlab.winehq.org/mono/wine-mono · https://gitlab.winehq.org/wine/wine-gecko |
| **winetricks** | LGPL-2.1-o-posterior (verificado en el encabezado del script) | Script fijado por versión (20260125), ejecutado con `/bin/sh` | https://github.com/Winetricks/winetricks |
| **DXMT** | MIT (verificado en el `LICENSE` de v0.80) | Se descarga solo si eliges el backend DXMT (experimental) y se superpone a una **copia** del motor Wine | https://github.com/3Shain/dxmt |
| **`winemac.so` de Wine 11.21 con parche de Dormer** | LGPL-2.1-or-later (es parte de Wine) | Compilado en CI desde el código oficial de Wine con el parche de `packaging/wine`; publicado en las *releases* del repositorio junto a su licencia y parche. Se descarga con DXMT y se coloca en la misma copia del motor | https://dl.winehq.org/wine/source/11.x/ · `packaging/wine/` |
| `cabextract` (sustituto) | — | **No se usa el programa original.** Dormer incluye un pequeño script propio (GPL-3.0-o-posterior) que usa el `bsdtar` de macOS | — |

## Lo que Dormer no incluye

- **D3DMetal / Game Porting Toolkit (Apple):** su licencia **prohíbe redistribuirlo**. Dormer nunca lo incluye ni lo descarga; si lo importas, se copia desde tu propio disco a tu carpeta de datos, solo en tu Mac.
- **Software de Microsoft:** los componentes que instala winetricks (Visual C++, .NET, DirectX, fuentes) se descargan **directamente de Microsoft u otras fuentes oficiales** a petición tuya y siguen sus propias licencias; Dormer no los redistribuye. Revisa y acepta sus términos antes de instalarlos.
- **DXVK-macOS:** no se ofrece (sin versiones desde 2024).

## Herramientas de desarrollo (no se distribuyen)

swift-format (Apache-2.0) y SwiftLint (MIT). Los íconos y recursos gráficos de Dormer son originales (generados con `Tools/make-icon.swift`).

---

*English:* Dormer (GPL-3.0-or-later) runs the components above as separate processes/files; none is linked into the app. Wine/Staging/winetricks are LGPL-2.1+, DXMT is MIT, Wine Mono/Gecko ship inside the downloaded Wine runtime under several free licenses. Apple's D3DMetal is never included (the user imports their own copy). Microsoft redistributables installed by winetricks are downloaded from official sources at the user's request and keep their own licenses.
