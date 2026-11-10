# OoT3D Editor

Editor de partidas de **The Legend of Zelda: Ocarina of Time 3D** que funciona **directamente en la Nintendo 3DS** (homebrew). No necesitas PC ni páginas web: respaldas la partida con Checkpoint, la editas en la consola y la restauras.

> 🇬🇧 English version below.

## ¿Qué puedes editar?

| Página | Contenido |
|---|---|
| Vida y magia | Corazones (hasta 20), rellenar vida, defensa doble, magia normal/doble |
| Rupias y bolsas | Rupias, bolsa de rupias, bolsas de palos, nueces, bombas y semillas, carcaj, guantes, escama |
| Munición | Palos, nueces, bombas, flechas, semillas, bombchus, judías mágicas |
| Objetos | Arco, gancho, boomerang, ocarina, flechas mágicas, hechizos, etc. |
| Botellas | Contenido de las 4 botellas |
| Equipo | Espadas (incluida la de Biggoron), escudos, túnicas, botas, Skulltulas doradas |
| Misión: canciones | Las 12 canciones |
| Misión: piedras y medallones | Piedras espirituales, medallones, Piedra de la Agonía, Pase Gerudo |

El editor recalcula el checksum de la partida al guardar y crea una copia `.orig` del archivo antes de modificarlo por primera vez. Si no reconoce el checksum, no deja editar.

## Requisitos

- Nintendo 3DS / 2DS (Old o New) con **custom firmware** (Luma3DS).
- **Homebrew Launcher**.
- **[Checkpoint](https://github.com/BernardoGiordano/Checkpoint)** para respaldar y restaurar partidas.
- Ocarina of Time 3D. **Probado con la versión de América (USA).** Las versiones europea y japonesa aparecen en el editor pero aún no se han probado.

## Instalación

1. Descarga `OoT3DEditor-vX.Y.Z.zip` de la sección **[Releases](../../releases/latest)**.
2. Descomprímelo en la **raíz** de la microSD. Debe quedar así:
   ```
   sd:/3ds/OoT3DEditor/OoT3DEditor.3dsx
   sd:/3ds/OoT3DEditor/OoT3DEditor.smdh
   sd:/3ds/OoT3DEditor/index.lua
   ```
3. Abre el Homebrew Launcher y verás **OoT3D Editor**.

## Uso

1. **Checkpoint** → Ocarina of Time 3D → **Backup**.
2. **Homebrew Launcher** → **OoT3D Editor** → elige el respaldo y el archivo de tu ranura:
   `save00.bin` = partida 1, `save01.bin` = partida 2, `save02.bin` = partida 3.
   (No abras `system.dat`, son solo las opciones del juego.)
3. Edita y pulsa **START** para guardar.
4. **Checkpoint** → Ocarina of Time 3D → elige el mismo respaldo → **Restore**.

### Controles

| Botón | Acción |
|---|---|
| Arriba / Abajo | Elegir opción |
| Izquierda / Derecha | Cambiar valor |
| Y + Izquierda / Derecha | Cambiar de 10 en 10 |
| A | Poner al máximo / activar |
| L / R (o ZL / ZR) | Página anterior / siguiente |
| START | Guardar |
| B | Volver (dos veces si hay cambios sin guardar) |

## ⚠️ Advertencias

- Haz **siempre** un respaldo con Checkpoint antes de editar. Úsalo bajo tu propia responsabilidad.
- Darte objetos que todavía no deberías tener puede romper la secuencia normal del juego.

## Para desarrolladores

- La app es un script Lua (`sd/3ds/OoT3DEditor/index.lua`) que corre sobre **Lua Player Plus (lpp-3ds)**. No hay que compilar nada: edita el `.lua` y cópialo a la SD.
- Formato de la partida: archivo de `0x14DC` bytes; checksum **CRC-16/ARC** en little-endian en `0x14D8`, calculado sobre todo el archivo con `0x14D8–0x14DB` en cero.
- Pruebas en PC (simulan la API de LPP):
  ```
  pip install lupa
  python tests/test_editor.py
  SAVE=ruta/a/save00.bin python tests/test_editor.py   # con una partida real (opcional)
  ```

## Créditos

- **[Lua Player Plus (lpp-3ds)](https://github.com/Rinnegatamante/lpp-3ds)** de Rinnegatamante — el intérprete incluido como `OoT3DEditor.3dsx` (GPL-3.0).
- **[OoT3D_Randomizer](https://github.com/gamestabled/OoT3D_Randomizer)** — referencia de la estructura de la partida (`z3D.h`).
- **[Checkpoint](https://github.com/BernardoGiordano/Checkpoint)** de Bernardo Giordano.
- `bannertool` (usado para crear el `.smdh`).

The Legend of Zelda y Ocarina of Time son marcas de Nintendo. Este proyecto no está afiliado ni respaldado por Nintendo y no incluye ningún archivo del juego.

## Licencia

[GPL-3.0](LICENSE).

---

## 🇬🇧 English

**OoT3D Editor** is an on-console save editor for *Ocarina of Time 3D* on Nintendo 3DS (homebrew). The interface is currently in Spanish.

**Install:** download the zip from [Releases](../../releases/latest) and extract it to the root of your SD card (`sd:/3ds/OoT3DEditor/`). Launch it from the Homebrew Launcher.

**Use:** back up the game with Checkpoint → open the backup's `save00.bin` (slot 1), `save01.bin` (slot 2) or `save02.bin` (slot 3) in OoT3D Editor → edit → press START to save → restore the backup with Checkpoint.

**Edits:** hearts, magic, double defense, rupees and wallet, all bag/quiver upgrades, ammo, items, bottles, swords (incl. Biggoron), shields, tunics, boots, songs, stones, medallions and Gold Skulltula tokens. The checksum (CRC-16/ARC) is recalculated on save and a `.orig` backup is created.

**Tested** with the USA version only. Always keep a Checkpoint backup. Licensed under GPL-3.0. Not affiliated with Nintendo.
