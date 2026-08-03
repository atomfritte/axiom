#!/usr/bin/env bash
# Erzeugt die Android-Symbole aus assets/brand/.
#
# Braucht rsvg-convert (librsvg). Aus der Projektwurzel ausfuehren.
set -euo pipefail

B=assets/brand
R=packages/axiom_app/android/app/src/main/res

command -v rsvg-convert >/dev/null || {
  echo "rsvg-convert fehlt (Paket: librsvg)"; exit 1
}

# Klassische Launcher-Symbole
for d in "mdpi 48" "hdpi 72" "xhdpi 96" "xxhdpi 144" "xxxhdpi 192"; do
  set -- $d
  mkdir -p "$R/mipmap-$1"
  rsvg-convert -w "$2" -h "$2" "$B/axiom-mark.svg" -o "$R/mipmap-$1/ic_launcher.png"
done

# Adaptives Symbol: Vordergrund 108dp, Motiv in der Safe Zone
for d in "mdpi 108" "hdpi 162" "xhdpi 216" "xxhdpi 324" "xxxhdpi 432"; do
  set -- $d
  mkdir -p "$R/drawable-$1"
  rsvg-convert -w "$2" -h "$2" "$B/axiom-icon-foreground.svg" \
    -o "$R/drawable-$1/ic_launcher_foreground.png"
done

echo "Symbole erzeugt. Hintergrundfarbe steht in res/values/colors.xml."
