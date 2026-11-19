# karukan, a Japanese input method for fcitx5 (https://github.com/togatoga/karukan). nixpkgs has no package, so build it here.
# CMake builds the Rust library with cargo and creates the fcitx5 addon that loads it
{
  lib,
  stdenv,
  # The karukan source, from the flake input inputs.karukan
  src,
  rustPlatform,
  cargo,
  rustc,
  cmake,
  pkg-config,
  kdePackages,
  fcitx5,
  libxkbcommon,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "fcitx5-karukan";
  # The only release is v0.1.0 from 2026-02 and much has changed since, so follow a commit on main.
  # A path: override has no lastModifiedDate, so fall back to "dirty"
  version = "0.1.0-unstable-" + (builtins.substring 0 8 (src.lastModifiedDate or "dirty"));
  inherit src;

  # Cargo.lock has no git dependencies, so fetch the dependency crates from Cargo.lock without writing a hash
  cargoDeps = rustPlatform.importCargoLock {
    lockFile = "${finalAttrs.src}/Cargo.lock";
  };

  cmakeDir = "../karukan-im/fcitx5/fcitx5-addon";
  # It is built on the machine that uses it, so tune for the CPU with -C target-cpu=native as upstream does by default (conversion gets about 5% faster).
  # CMake's KARUKAN_NATIVE has no effect when RUSTFLAGS is in the environment, so pass it directly through RUSTFLAGS.
  # The result runs only on the CPU of the machine that built it, yet the derivation hash does not change, so do not carry it to other machines
  env.RUSTFLAGS = "-C target-cpu=native";

  nativeBuildInputs = [
    cmake
    pkg-config
    kdePackages.extra-cmake-modules
    cargo
    rustc
    rustPlatform.cargoSetupHook
    # llama-cpp-sys-2 needs libclang to generate FFI bindings with bindgen
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    fcitx5
    libxkbcommon
  ];

  meta = {
    description = "Japanese input method with neural kana-kanji conversion for fcitx5";
    homepage = "https://github.com/togatoga/karukan";
    license = with lib.licenses; [
      mit
      asl20
    ];
    platforms = lib.platforms.linux;
  };
})
