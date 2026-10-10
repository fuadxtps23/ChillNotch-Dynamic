# Maintainer: fuadxtps23
pkgname=chillnotch-dynamic
pkgver=0.1.0
pkgrel=1
pkgdesc="Quickshell notch-style dynamic pill bar for Hyprland"
arch=('x86_64')
url="https://github.com/fuadxtps23/ChillNotch-Dynamic"
license=('GPL-3.0-or-later')
depends=('quickshell' 'hyprland' 'qt6-base' 'qt6-declarative' 'qt6-multimedia'
         'cliphist' 'brightnessctl' 'wl-clipboard' 'inotify-tools'
         'python-psutil' 'blueman' 'pipewire' 'networkmanager' 'libpulse'
         'upower' 'libnotify')
makedepends=('cmake')
options=('!debug')
optdepends=('wf-recorder: screen recording (Control Center Record button)'
            'slurp: select-region recording'
            'ffmpeg: probe working video encoders for recording'
            'power-profiles-daemon: power profile button'
            'hyprlock: lock action'
            'matugen: wallpaper color generation'
            'cava: audio visuals in media player'
            'awww: wallpaper switcher'
            'nusgmon: data usage module'
            'python-holidays: event dates in calendar'
            'qt6-imageformats: WEBP wallpaper previews'
            'ttf-jetbrains-mono-nerd: icons and font')
source=("$pkgname-$pkgver.tar.gz::$url/archive/refs/tags/v$pkgver.tar.gz")
sha256sums=('SKIP')

build() {
  cd "ChillNotch-Dynamic-$pkgver"
  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
  cmake --build build
}

package() {
  cd "ChillNotch-Dynamic-$pkgver"
  local share="$pkgdir/usr/share/$pkgname"

  install -Dm644 build/libIslandBackend.so build/libIslandBackendPlugin.so \
    build/qmldir build/IslandBackend.qmltypes -t "$share/IslandBackend"

  install -Dm644 qml/* -t "$share"
  install -Dm755 scripts/* -t "$share/scripts"
  install -Dm644 scripts/cava.conf -t "$share/scripts"
  install -Dm644 share/* -t "$share/share"
  install -Dm644 config.jsonc "$share/config.jsonc.example"

  install -Dm755 launcher.sh "$pkgdir/usr/bin/$pkgname"
  install -Dm644 "$pkgname.desktop" -t "$pkgdir/usr/share/applications"
  # install.sh uses /usr/local/bin; the package installs to /usr/bin
  sed -i 's|/usr/local/bin/|/usr/bin/|' "$pkgdir/usr/share/applications/$pkgname.desktop"
  # backend lives in the shared dir, not ~/.config
  sed -i "s|\$HOME/.config/quickshell/chillnotch-dynamic/IslandBackend|/usr/share/$pkgname/IslandBackend|" "$pkgdir/usr/bin/$pkgname"
  install -Dm644 LICENSE -t "$pkgdir/usr/share/licenses/$pkgname"
}
