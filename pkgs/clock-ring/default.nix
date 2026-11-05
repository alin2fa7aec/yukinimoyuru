# A round wall clock with an audio spectrum drawn around it (clock-ring.py).
# Using gtk4-layer-shell from Python requires loading it before libwayland-client, so inject it with LD_PRELOAD
{
  lib,
  stdenvNoCC,
  python3,
  wrapGAppsHook4,
  gobject-introspection,
  gtk4,
  gtk4-layer-shell,
  cava,
}:

stdenvNoCC.mkDerivation {
  pname = "clock-ring";
  version = "0.1.0";

  src = ./clock-ring.py;
  dontUnpack = true;

  nativeBuildInputs = [
    wrapGAppsHook4
    gobject-introspection
  ];
  buildInputs = [
    gtk4
    gtk4-layer-shell
    (python3.withPackages (ps: [
      ps.pygobject3
      ps.pycairo
    ]))
  ];

  installPhase = ''
    install -Dm755 $src $out/bin/clock-ring
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : ${lib.makeBinPath [ cava ]}
      --set LD_PRELOAD ${gtk4-layer-shell}/lib/libgtk4-layer-shell.so
    )
  '';
}
