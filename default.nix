{ pkgs ? import <nixpkgs> {} }:

let
qtModules = with pkgs.qt6; [
  qtbase
  qtdeclarative
  qtmultimedia
];
qmlImportPath = pkgs.lib.concatMapStringsSep ":" (m: "${m}/lib/qt-6/qml") qtModules;
qtPluginPath  = pkgs.lib.concatMapStringsSep ":" (m: "${m}/lib/qt-6/plugins") qtModules;

nusgmonPython = pkgs.python3.withPackages (ps: [ ps.psutil ]);
scriptsPython = pkgs.python3.withPackages (ps: [ ps.holidays ]);

nusgmon = pkgs.stdenv.mkDerivation {
  pname = "nusgmon";
  version = "unstable-2024";
  src = pkgs.fetchFromGitHub {
    owner = "LUCKYS1NGHH";
    repo = "nusgmon";
    rev = "a896594";
    sha256 = "sha256-WTJ/jr+MawJsSIXAGi7itEo8/QJ54Po4FJ2ASw8/64Q=";
  };

  nativeBuildInputs = [ pkgs.makeWrapper ];

  installPhase = ''
    mkdir -p $out/share/nusgmon
    cp -r . $out/share/nusgmon

    makeWrapper ${nusgmonPython}/bin/python3 $out/bin/nusgmon \
      --add-flags "$out/share/nusgmon/nusgmon"

    install -Dm644 config.toml $out/share/nusgmon/config.toml.example
  '';
};

   runtimeDeps = with pkgs; [
     cava
     quickshell
     cliphist
     brightnessctl
     wl-clipboard
     inotify-tools
     pipewire
     pulseaudio
     blueman
     awww
     nusgmon
     networkmanager
     libnotify
     upower
     wf-recorder
     slurp
     ffmpeg
     power-profiles-daemon
     matugen
   ];
in
pkgs.stdenv.mkDerivation rec {
  pname = "chillnotch-dynamic";
  version = "0.1.0";

  src = ./.;

  nativeBuildInputs = with pkgs; [
    cmake
    pkg-config
    qt6.wrapQtAppsHook
    makeWrapper
  ];

  buildInputs = with pkgs; [
    qt6.qtbase
    qt6.qtdeclarative
    qt6.qttools
    qt6.qtmultimedia
  ];

  cmakeFlags = [
    "-DCMAKE_INSTALL_LIBDIR=lib"
  ];

  installPhase = ''
    runHook preInstall

    cmake --install .

    install -Dm755 $src/launcher.sh $out/bin/chillnotch-dynamic
    substituteInPlace $out/bin/chillnotch-dynamic \
      --replace '/usr/share/chillnotch-dynamic' "$out/share/chillnotch-dynamic" \
      --replace '$HOME/.config/quickshell/chillnotch-dynamic/IslandBackend' "$out/lib/qt6/qml/IslandBackend"

    cat > $out/bin/chillnotch-dynamic-ipc <<'WRAPPER'
  #!/usr/bin/env bash
  exec REPLACE_QS ipc -p REPLACE_CONFIG_PATH "$@"
  WRAPPER
    chmod +x $out/bin/chillnotch-dynamic-ipc
    substituteInPlace $out/bin/chillnotch-dynamic-ipc \
      --replace REPLACE_QS "${pkgs.quickshell}/bin/qs" \
      --replace REPLACE_CONFIG_PATH "$out/share/chillnotch-dynamic"

    mkdir -p $out/share/chillnotch-dynamic
    cp -r $src/qml/*   $out/share/chillnotch-dynamic/
    cp -r $src/share   $out/share/chillnotch-dynamic/
    cp -r $src/scripts $out/share/chillnotch-dynamic/
    install -Dm644 $src/config.jsonc $out/share/chillnotch-dynamic/config.jsonc.example

    chmod +x $out/share/chillnotch-dynamic/scripts/*
    PATH="${scriptsPython}/bin:$PATH" patchShebangs $out/share/chillnotch-dynamic/scripts

    grep -rl '/usr/share/chillnotch-dynamic' $out/share/chillnotch-dynamic | while read -r f; do
      substituteInPlace "$f" --replace '/usr/share/chillnotch-dynamic' "$out/share/chillnotch-dynamic"
    done

    install -Dm644 $src/chillnotch-dynamic.desktop $out/share/applications/chillnotch-dynamic.desktop
    substituteInPlace $out/share/applications/chillnotch-dynamic.desktop \
      --replace 'Exec=chillnotch-dynamic' "Exec=$out/bin/chillnotch-dynamic"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram $out/bin/chillnotch-dynamic \
      --set QML_IMPORT_PATH "$out/share/chillnotch-dynamic:$out/lib/qt6/qml:${qmlImportPath}" \
      --set QT_PLUGIN_PATH "${qtPluginPath}" \
      --set LD_LIBRARY_PATH "$out/lib/qt6/qml/IslandBackend" \
      --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps}
  '';

  meta = with pkgs.lib; {
    description = "ChillNotch (Wayland bar) fork - chillnotch-dynamic";
    homepage = "https://github.com/PinguinAdvokat/chillnotch-dynamic";
    license = licenses.gpl3Plus;
    platforms = platforms.linux;
    mainProgram = "chillnotch-dynamic";
  };
}
