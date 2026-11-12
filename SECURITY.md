# Política de seguridad · Security policy

## Versiones con soporte

Dormer está en desarrollo inicial (0.x). Solo la última versión publicada recibe correcciones de seguridad.

## Cómo reportar una vulnerabilidad

**No abras un *issue* público.** Usa los avisos privados de seguridad de GitHub («Security» → «Report a vulnerability») o el contacto privado del perfil del repositorio. Incluye: versión de Dormer y de macOS, pasos para reproducir y el impacto que ves. Responderemos en cuanto podamos y te daremos crédito si quieres.

## Qué consideramos una vulnerabilidad

- Descargas que se instalan sin verificar su SHA-256, o que no usan HTTPS.
- Un archivo de botella `.aar` que, al importarse, escribe fuera de la carpeta de datos de Dormer (por ejemplo, con `..`, rutas absolutas o enlaces simbólicos).
- Ejecutar comandos del sistema con datos controlados por un archivo externo (un nombre de programa, un acceso directo, un nombre de verbo).
- Que un programa dentro de una botella marcada como aislada vea el disco del Mac sin que el usuario lo haya permitido.
- Filtración de datos personales en «Copiar para reporte».

## Qué no lo es

Wine ejecuta programas de Windows **sin sandbox de seguridad**: un programa malicioso dentro de una botella puede dañar lo que la botella pueda tocar. Por eso Dormer avisa antes de ejecutar archivos descargados, oculta el disco del Mac por defecto y aísla cada programa en su botella, pero **no es una máquina virtual ni un antivirus**. No ejecutes software en el que no confíes.

## Lo que Dormer hace para protegerte

- Todas las descargas (Wine, winetricks, DXMT) son por HTTPS y se comprueban contra tamaño y SHA-256 fijados en el propio código; un archivo que no coincide se borra.
- Los archivos de botella se validan **antes** de extraerlos.
- Sin telemetría, sin cuentas y sin servicios en la nube.
- Todo se guarda en `~/Library/Application Support/Dormer/` (y los lanzadores que tú crees).

---

*English:* Please do **not** file public issues for vulnerabilities; use GitHub private security advisories. In scope: unverified or non-HTTPS downloads, path traversal in imported bottles, command injection through external data, host-filesystem exposure in isolated bottles, and PII leaks in the report text. Out of scope: Wine itself has no security sandbox — Dormer is not a VM or antivirus.
