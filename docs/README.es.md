# atieclxx-fix (guía rápida en español)

`atieclxx.exe` (AMD External Events Utility), que viene con el driver de AMD Radeon, tiene un fallo: cada segundo copia su propio archivo (677 KB) al disco del sistema, lo que suma **40–55 GB al día**, incluso con el PC en reposo. Esta solución bloquea solo esa copia. El servicio de AMD sigue funcionando, así que FreeSync y los atajos siguen funcionando.

Explicación completa (en inglés): [README](../README.md)

## ¿Todavía lo necesito?

AMD corrigió el fallo en **Adrenalin 26.11.1** (12 de noviembre de 2026) para RX 7000 y posteriores. Las tarjetas Polaris y Vega todavía no están corregidas.

| Tu tarjeta | Qué hacer |
|---|---|
| **RX 7000, RX 9000** | Actualiza a Adrenalin 26.11.1. Si aplicaste esta solución, ejecútala otra vez y pulsa **U** (deshacer) y luego **C** (comprobar). |
| **RX 5000, RX 6000** | No aparecen en las notas de AMD. Actualiza y pulsa **C**. Si dice AFFECTED, pulsa **F**. |
| **Serie RX 400/500 (como la RX 580), Vega** | **AMD todavía no lo ha corregido. Usa esta solución (pasos abajo).** |

## Cómo usarlo

1. Descarga **[atieclxx-fix.zip](https://github.com/candygoogy/atieclxx-fix/releases/latest/download/atieclxx-fix.zip)** y descomprímelo.
2. Haz doble clic en **`Fix-SSD-Writes.cmd`** y acepta el aviso de administrador.
3. Pulsa **F**.

El script mide las escrituras, aplica la solución y vuelve a medir, para que veas cómo el número baja a cero. Si tu PC no tiene el problema, no cambia nada.

- **C**: solo comprueba, sin cambiar nada. `AFFECTED` significa afectado; `OK` significa que todo está bien.
- **U**: deshace la solución.
- Si Windows muestra "Windows protegió su PC", haz clic en **Más información → Ejecutar de todas formas**. Windows lo muestra con cualquier script descargado de internet. La solución entera es un único archivo de PowerShell que se puede leer.
- Después de actualizar el driver de AMD, ejecútala otra vez y pulsa **F**.

¿Dudas o resultados? Abre un [issue](https://github.com/candygoogy/atieclxx-fix/issues) (puede ser en español) con la salida de **C**.
