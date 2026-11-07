# A round wall clock with an audio spectrum drawn around it (src/main.rs).
# It draws on a wlr-layer-shell surface by itself, so it needs no GUI toolkit. cava is put on PATH for the spectrum
{
  lib,
  rustPlatform,
  pkg-config,
  makeWrapper,
  cairo,
  pango,
  glib,
  cava,
}:

rustPlatform.buildRustPackage {
  pname = "clock-ring";
  version = "0.2.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./Cargo.toml
      ./Cargo.lock
      ./src
    ];
  };

  cargoLock.lockFile = ./Cargo.lock;

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ];
  buildInputs = [
    cairo
    pango
    glib
  ];

  postInstall = ''
    wrapProgram $out/bin/clock-ring --prefix PATH : ${lib.makeBinPath [ cava ]}
  '';

  meta = {
    description = "Wall clock with an audio spectrum ring, drawn on a wlr-layer-shell surface";
    license = lib.licenses.mit;
    mainProgram = "clock-ring";
    platforms = lib.platforms.linux;
  };
}
