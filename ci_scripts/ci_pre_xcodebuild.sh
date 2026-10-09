#!/bin/sh
# Xcode Cloud: roda antes de cada xcodebuild.
#
# No Xcode 26 o compilador Metal virou um componente separado ("Metal Toolchain").
# Algumas imagens do Xcode Cloud vêm sem ele, e o Shaders/Bubble.metal falha com
# "Command CompileMetalFile failed with a nonzero exit code" (+ aviso de Bubble.dia ausente).
# Aqui garantimos que o toolchain está instalado antes do build.

set -u

echo "== Xcode: $(xcodebuild -version | tr '\n' ' ')"

if xcrun -f metal >/dev/null 2>&1 && xcodebuild -showComponent MetalToolchain 2>/dev/null | grep -q "Status: installed"; then
    echo "== Metal Toolchain já instalado."
else
    echo "== Metal Toolchain ausente; baixando..."
    xcodebuild -downloadComponent MetalToolchain || echo "!! downloadComponent falhou (veja o log acima)."
fi

xcodebuild -showComponent MetalToolchain 2>&1 || true
xcrun -f metal 2>&1 || echo "!! 'metal' ainda não encontrado; o CompileMetalFile vai falhar."

exit 0
