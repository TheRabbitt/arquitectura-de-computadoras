#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# scripts/vivado.sh
#
# Lanza Vivado desde WSL o desde Linux nativo, sin que el que llama tenga que
# saber cual de los dos es.
#
# El problema que resuelve: en WSL, vivado.bat NO se puede ejecutar directo.
# WSL lanza automaticamente ejecutables de Windows solo si son .exe. Un .bat
# es texto plano, y como /mnt/c monta todo con permiso de ejecucion, Linux
# intenta correrlo con /bin/sh y devuelve una catarata de "rem: not found".
# Hay que pasarlo por cmd.exe, que es el interprete que le corresponde.
#
# Uso:
#   VIVADO=/mnt/c/.../vivado.bat scripts/vivado.sh -mode batch -source x.tcl
# ---------------------------------------------------------------------------
set -euo pipefail

if [ -z "${VIVADO:-}" ]; then
    echo "ERROR: la variable VIVADO no esta definida." >&2
    echo "       Fijala en el Makefile o corre 'make find-vivado'." >&2
    exit 1
fi

if [ ! -e "$VIVADO" ]; then
    echo "ERROR: no existe: $VIVADO" >&2
    exit 1
fi

case "$VIVADO" in
    *.bat|*.BAT)
        # --- Vivado de Windows, invocado desde WSL ---
        command -v cmd.exe >/dev/null 2>&1 || {
            echo "ERROR: no se encuentra cmd.exe." >&2
            echo "       La interoperabilidad de WSL con Windows esta deshabilitada." >&2
            echo "       Revisar /etc/wsl.conf -> [interop] enabled=true" >&2
            exit 1
        }

        # cmd.exe no puede trabajar con un cwd del filesystem de WSL.
        case "$PWD" in
            /mnt/*) ;;
            *)
                echo "ERROR: el repo esta en $PWD, fuera de /mnt/." >&2
                echo "       cmd.exe no puede usar ese directorio como cwd." >&2
                echo "       Mover el repo a /mnt/e/... o /mnt/c/..." >&2
                exit 1
                ;;
        esac

        win_bat=$(wslpath -w "$VIVADO")
        echo "[vivado.sh] cmd.exe /C $win_bat $*"
        exec cmd.exe /C "$win_bat" "$@"
        ;;
    *)
        # --- Vivado de Linux ---
        exec "$VIVADO" "$@"
        ;;
esac