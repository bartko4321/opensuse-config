#!/bin/bash

# ==========================================================
# KOMPLEKSOWY SKRYPT KONFIGURACYJNY SYSTEMU openSUSE TUMBLEWEED
# ==========================================================

set -euo pipefail
export ZYPPER_NONINTERACTIVE=1

# --- Kolory ---
INFO='\033[0;34m'
SUCCESS='\033[0;32m'
ERROR='\033[0;31m'
WARN='\033[0;33m'
NC='\033[0m'

log_info()  { echo -e "${INFO}==> $*${NC}"; }
log_ok()    { echo -e "${SUCCESS}✔ $*${NC}"; }
log_err()   { echo -e "${ERROR}✖ BŁĄD: $*${NC}" >&2; }
log_warn()  { echo -e "${WARN}⚠ UWAGA: $*${NC}"; }

# Pułapka błędów
trap 'log_err "Skrypt zakończył się błędem w linii $LINENO. Polecenie: $BASH_COMMAND"' ERR

# Upewnij się, że skrypt NIE jest uruchamiany jako root
if [[ "$EUID" -eq 0 ]]; then
    log_err "Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z uprawnieniami sudo."
    exit 1
fi

# --- Zmienne ---
CURRENT_USER=$(whoami)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RPM_DIR="$(mktemp -d /tmp/rpm_install_XXXXXX)"

OPTIONAL_PACKAGES=()
PACKAGES_32_OPTIONAL=()

# Tymczasowy wyjątek sudo dla Zypper/RPM (by nie pytało o hasło podczas instalacji)
sudo -v
echo "$CURRENT_USER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/99-temp-installer > /dev/null

# Dodatkowe pliki
if [[ -f "$SCRIPT_DIR/.update.sh" ]]; then
    cp -af "$SCRIPT_DIR/.update.sh" ~/.update.sh
    chmod +x ~/.update.sh
fi

# ── Kopiowanie .local i .config do katalogu domowego ──────────
if [[ -d "$SCRIPT_DIR/.local" ]]; then
    mkdir -p ~/.local
    cp -afT "$SCRIPT_DIR/.local" ~/.local
    log_ok "Skopiowano katalog '.local' do \$HOME"
else
    log_warn "Brak katalogu '.local' w katalogu skryptu – pominięto"
fi

if [[ -d "$SCRIPT_DIR/.config" ]]; then
    mkdir -p ~/.config
    cp -afT "$SCRIPT_DIR/.config" ~/.config
    log_ok "Skopiowano katalog '.config' do \$HOME"
else
    log_warn "Brak katalogu '.config' w katalogu skryptu – pominięto"
fi

# ==========================================================
# 1. KONFIGURACJA SYSTEMOWA (SUDO)
# ==========================================================
log_info "Przechodzę do konfiguracji systemowej (openSUSE Tumbleweed)..."

# Wyłączenie PackageKit, aby uniknąć problemów z blokadą bazy Zypper
log_info "Zatrzymywanie usług w tle (PackageKit)..."
sudo systemctl stop packagekit.service 2>/dev/null || true
sudo killall -9 packagekitd 2>/dev/null || true

# Wczesna instalacja krytycznych zależności do działania skryptu
log_info "Instalacja podstawowych zależności (curl, wget, pciutils)..."
sudo zypper install -y curl wget pciutils

# --- Dodanie repozytoriów ---

# Packman (kodeki, Wine staging, itp.)
log_info "Dodawanie repozytorium Packman..."
sudo zypper addrepo -cfp 90 https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/ packman \
    || log_warn "Repozytorium Packman już dodane"
sudo rpm --import https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/repodata/repomd.xml.key 2>/dev/null || true

# Repozytorium games (gamemode, mangohud, gamescope)
log_info "Dodawanie repozytorium games..."
sudo zypper addrepo -cfp 80 https://download.opensuse.org/repositories/games/openSUSE_Tumbleweed/ games \
    || log_warn "Repozytorium games już dodane"

# Repozytorium Emulators
log_info "Dodawanie repozytorium emulators..."
sudo zypper addrepo -cfp 80 https://download.opensuse.org/repositories/Emulators/openSUSE_Tumbleweed/ emulators \
    || log_warn "Repozytorium Emulators już dodane"

# Repozytorium Emulators:Wine (dla najnowszego Wine)
log_info "Dodawanie repozytorium Emulators:Wine..."
sudo zypper addrepo -cfp 80 https://download.opensuse.org/repositories/Emulators:/Wine/openSUSE_Tumbleweed/ emulators-wine \
    || log_warn "Repozytorium Emulators:Wine już dodane"

# Google Chrome
log_info "Dodawanie repozytorium Google Chrome..."
sudo zypper addrepo -cfp 80 https://dl.google.com/linux/chrome/rpm/stable/x86_64 google-chrome \
    || log_warn "Repozytorium Google Chrome już dodane"
sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null || true

# Brave (Origin) - wg https://brave.com/origin/linux/
log_info "Dodawanie repozytorium Brave Origin..."

# UWAGA: klucz podpisujący hostowany przez Brave na S3 (brave-core.asc,
# do którego odwołuje się plik .repo poniżej) bywa nieaktualny względem
# tego, czym faktycznie podpisują metadane repo — znany, powtarzający się
# problem po stronie Brave (np. https://github.com/brave/brave-browser/issues/34373
# i #42949), objawiający się błędem weryfikacji podpisu przy odświeżaniu repo
# ("Signing key not found" / brak dopasowanego klucza GPG). Dlatego importujemy
# klucz RĘCZNIE, zanim zypper spróbuje go auto-zaimportować z (być może
# nieaktualnego) pliku Brave: najpierw próbujemy oficjalnego brave-core.asc,
# a jeśli import się nie uda, pobieramy ten sam klucz po jego ID bezpośrednio
# z niezależnego keyservera.
sudo zypper install -y gpg2 2>/dev/null || true
BRAVE_KEY_ID="0686B78420038257"
if ! sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc 2>/dev/null; then
    log_warn "Import klucza Brave z brave-core.asc nie powiódł się, próbuję keyservera..."
    BRAVE_GNUPGHOME="$(mktemp -d)"
    if ! gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keyserver.ubuntu.com --recv-keys "$BRAVE_KEY_ID"; then
        log_warn "keyserver.ubuntu.com nie odpowiedział, próbuję keys.openpgp.org..."
        gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keys.openpgp.org --recv-keys "$BRAVE_KEY_ID"
    fi
    gpg --homedir "$BRAVE_GNUPGHOME" --armor --export "$BRAVE_KEY_ID" > "$BRAVE_GNUPGHOME/brave-core.asc"
    sudo rpm --import "$BRAVE_GNUPGHOME/brave-core.asc"
    rm -rf "$BRAVE_GNUPGHOME"
fi

sudo zypper addrepo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
    || log_warn "Repozytorium Brave już dodane"

# Odśwież repozytoria
log_info "Odświeżanie repozytoriów..."
sudo zypper --gpg-auto-import-keys refresh

# Aktualizacja systemu
log_info "Aktualizacja systemu (dup)..."
sudo zypper dup -y --allow-vendor-change

# --- Przeglądarki ---
log_info "Instalacja przeglądarek..."
sudo zypper install -y google-chrome-stable || log_warn "Instalacja Chrome nie powiodła się"
sudo zypper install -y brave-origin || log_warn "Instalacja Brave nie powiodła się"

# --- Czyszczenie zbędnych pakietów ---
log_info "Usuwanie zbędnych pakietów..."
TO_REMOVE=(
    opensuse-welcome-launcher plasma-welcome imagemagick 
    nano konqueror plasma-browser-integration plasma-vault 
    plasma-thunderbolt kontact kmail kontrast krdp krfb 
    kaddressbook kdepim-runtime akonadi-server akregator 
    epiphany decibels rhythmbox korganizer 
    showtime cosmic-player parole kwalletmanager
)
for pkg in "${TO_REMOVE[@]}"; do
    if rpm -q "$pkg" &>/dev/null; then
        sudo zypper remove -y "$pkg" 2>/dev/null \
            && log_ok "Usunięto: $pkg" \
            || log_warn "Nie udało się usunąć: $pkg — pomijam"
    fi
done
sudo zypper autoremove -y 2>/dev/null || true

# --- Główna lista pakietów ---
PACKAGES=(
    # Narzędzia systemowe
    dconf-editor fastfetch unrar git mc android-tools pv zenity innoextract
    # Multimedia
    elisa audacity vlc gimp gmic mixxx kdenlive kolourpaint soundconverter handbrake-gui
    # Internet / komunikatory
    telegram-desktop qbittorrent thunderbird MozillaThunderbird-translations-common
    # Narzędzia
    bleachbit makeself vim cdemu-daemon cdemu-client 
    # Gaming / Vulkan / render
    gamemode gamescope mangohud goverlay libvkd3d1 wine-staging wine-mono wine-gecko
    # Kompilatory i build tools
    cmake meson patterns-devel-base-devel_basis kernel-devel
    # GStreamer
    gstreamer-plugins-ugly
    # Powłoka
    zsh
)

log_info "Instalacja głównej listy pakietów 64-bit..."
for pkg in "${PACKAGES[@]}"; do
    if sudo zypper install -y --allow-vendor-change "$pkg" 2>/dev/null; then
        continue
    fi
    # Niektóre pakiety (np. handbrake-gui) istnieją tylko w Packman i zdarza
    # się, że zwykłe rozstrzygnięcie dostawcy ich nie znajdzie — spróbuj
    # jawnie z tego repozytorium, zanim uznamy pakiet za niedostępny.
    if sudo zypper install -y --allow-vendor-change --from packman "$pkg" 2>/dev/null; then
        log_ok "Zainstalowano z Packman: $pkg"
    else
        log_warn "Pominięto pakiet: $pkg (niedostępny)"
    fi
done

log_info "Instalacja opcjonalnych pakietów..."
for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    sudo zypper install -y --allow-vendor-change "$pkg" 2>/dev/null \
        && log_ok "Zainstalowano: $pkg" \
        || log_warn "Pakiet $pkg niedostępny — pomijam"
done


# ==========================================================
# 2. WYKRYWANIE GPU: BIBLIOTEKI 32-BIT I DRACUT (EARLY KMS)
# ==========================================================
log_info "Wykrywanie sprzętu w celu instalacji bibliotek 32-bitowych i konfiguracji dracut (Early KMS)..."

PACKAGES_32=(
    mangohud-32bit libgamemodeauto0-32bit libvkd3d1-32bit wine-staging-32bit
    libopenal1-32bit libXdamage1-32bit libXtst6-32bit
    libgtk-2_0-0-32bit libgtk-3-0-32bit
)

GPU_VENDOR=$(lspci -nn | grep -iE "VGA|3D|Display" || true)
DRACUT_CONF="/etc/dracut.conf.d/90-gpu.conf"

if echo "$GPU_VENDOR" | grep -iq "nvidia"; then
    log_ok "Wykryto układ NVIDIA. Dodaję biblioteki GLVND oraz moduły dracut..."
    PACKAGES_32+=(libglvnd-32bit)
    echo 'force_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "' | sudo tee "$DRACUT_CONF" > /dev/null

elif echo "$GPU_VENDOR" | grep -iqE "amd|radeon"; then
    log_ok "Wykryto układ AMD. Dodaję biblioteki Mesa oraz moduł amdgpu..."
    PACKAGES_32+=(libvulkan_radeon-32bit)
    echo 'force_drivers+=" amdgpu "' | sudo tee "$DRACUT_CONF" > /dev/null

elif echo "$GPU_VENDOR" | grep -iq "intel"; then
    log_ok "Wykryto układ Intel. Dodaję biblioteki Mesa oraz moduł i915..."
    PACKAGES_32+=(libvulkan_intel-32bit)
    echo 'force_drivers+=" i915 "' | sudo tee "$DRACUT_CONF" > /dev/null

else
    log_warn "Nie udało się jednoznacznie wykryć GPU. Używam ustawień generycznych."
    sudo rm -f "$DRACUT_CONF"
fi

log_info "Instalacja bibliotek 32-bitowych..."
for pkg in "${PACKAGES_32[@]}"; do
    sudo zypper install -y --allow-vendor-change "$pkg" 2>/dev/null || log_warn "Pominięto 32-bit: $pkg"
done

log_info "Instalacja opcjonalnych bibliotek 32-bitowych..."
for pkg in "${PACKAGES_32_OPTIONAL[@]}"; do
    sudo zypper install -y --allow-vendor-change "$pkg" 2>/dev/null || log_warn "Pakiet $pkg niedostępny — pomijam"
done

if [[ -f "$DRACUT_CONF" ]]; then
    log_info "Przebudowa obrazu initramfs (dracut) dla wczesnego KMS..."
    sudo dracut --force
fi


# ==========================================================
# 3. PAKIETY RPM POBIERANE RĘCZNIE I FLATPAK
# ==========================================================
log_info "Pobieranie i instalacja zewnętrznych pakietów..."

download_rpm() {
    local name="$1" url="$2" dest="$3"
    if wget -q --timeout=30 -O "$dest" "$url"; then
        log_ok "Pobrano: $name"
    else
        log_warn "Nie udało się pobrać: $name ($url) — pomijam"
        rm -f "$dest"
    fi
}

install_discord_rpm() {
    local dest="$RPM_DIR/discord.rpm"
    if wget -q --user-agent="Mozilla/5.0" "https://discord.com/api/download?platform=linux&format=rpm" -O "$dest"; then
        if file "$dest" | grep -q "RPM"; then
            sudo zypper install -y --allow-unsigned-rpm "$dest"
            rm -f "$dest"
        else
            log_err "Pobrany plik nie jest poprawną paczką RPM. Discord blokuje pobieranie."
            rm -f "$dest"
        fi
    else
        log_warn "Nie udało się połączyć z serwerem Discord."
    fi
}

# Discord
if sudo zypper repos | grep -iq "packman"; then
    sudo zypper install -y discord \
        && log_ok "Discord zainstalowany z repozytorium Packman." \
        || { log_warn "Błąd instalacji Discorda. Próbuję pobrać RPM ręcznie..."; install_discord_rpm; }
else
    log_warn "Repozytorium Packman niewykryte. Próbuję pobrać RPM ręcznie..."
    install_discord_rpm
fi

# ls-fg i ls-fg-vk (GitHub)
LSFG_URL=$(curl -sf https://api.github.com/repos/YuriSizov/ls-fg/releases/latest | grep "browser_download_url.*ls-fg_.*rpm" | cut -d '"' -f 4 || true)
[[ -n "$LSFG_URL" ]] && download_rpm "ls-fg" "$LSFG_URL" "$RPM_DIR/lsfg.rpm"

LSFG_VK_URL=$(curl -sf https://api.github.com/repos/YuriSizov/ls-fg-vk/releases/latest | grep "browser_download_url.*rpm" | cut -d '"' -f 4 || true)
[[ -n "$LSFG_VK_URL" ]] && download_rpm "ls-fg-vk" "$LSFG_VK_URL" "$RPM_DIR/lsfg-vk.rpm"

# Faugus Launcher (GitHub) — dostępny tylko jako RPM budowany dla Fedory,
# więc doinstalowujemy zależności Pythona przez pip i pomijamy sprawdzanie
# zależności RPM przy instalacji (--nodeps).
log_info "Instalacja Faugus Launcher (GitHub)..."
sudo zypper install -y --allow-vendor-change \
    python3-gobject python3-Pillow python3-psutil python3-requests \
    libcanberra-gtk3-module vulkan-tools ImageMagick 2>/dev/null \
    || log_warn "Część zależności Faugus Launcher niedostępna w repozytoriach — kontynuuję"

sudo pip3 install --break-system-packages -q vdf icoextract pygame 2>/dev/null \
    || log_warn "Nie udało się doinstalować modułów pip dla Faugus Launcher (vdf/icoextract/pygame)"

FAUGUS_URL=$(curl -sf https://api.github.com/repos/Faugus/faugus-launcher/releases/latest \
    | grep "browser_download_url.*noarch.rpm" | cut -d '"' -f 4 || true)

if [[ -n "$FAUGUS_URL" ]]; then
    FAUGUS_RPM="$RPM_DIR/faugus-launcher-standalone.rpm"
    download_rpm "faugus-launcher" "$FAUGUS_URL" "$FAUGUS_RPM"
    if [[ -f "$FAUGUS_RPM" ]]; then
        sudo rpm -Uvh --nodeps --force "$FAUGUS_RPM" \
            && log_ok "Zainstalowano Faugus Launcher" \
            || log_warn "Instalacja Faugus Launcher nie powiodła się"
        rm -f "$FAUGUS_RPM"
    fi
else
    log_warn "Nie udało się znaleźć pakietu RPM Faugus Launcher na GitHub — pomijam"
fi

# Flathub (repozytorium Flatpak)
log_info "Dodawanie repozytorium Flathub..."
sudo zypper install -y flatpak 2>/dev/null || true
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo \
    && log_ok "Repozytorium Flathub dodane" \
    || log_warn "Nie udało się dodać repozytorium Flathub"

log_info "Odświeżanie metadanych Flathub..."
flatpak update --appstream 2>/dev/null || log_warn "Nie udało się odświeżyć metadanych Flathub"

# Flatseal (Flatpak)
log_info "Instalacja Flatseal przez Flatpak..."
flatpak install --user -y flathub com.github.tchx84.Flatseal 2>/dev/null \
    && log_ok "Flatseal zainstalowany" \
    || log_warn "Instalacja Flatseal nie powiodła się — pomijam"

# Gear Lever (Flatpak)
log_info "Instalacja Gear Lever przez Flatpak..."
flatpak install --user -y flathub it.mijorus.gearlever 2>/dev/null \
    && log_ok "Gear Lever zainstalowany" \
    || log_warn "Instalacja Gear Lever nie powiodła się — pomijam"

# Instalacja zebranych plików RPM
shopt -s nullglob
RPM_FILES=("$RPM_DIR"/*.rpm)
if [[ ${#RPM_FILES[@]} -gt 0 ]]; then
    sudo zypper install -y --allow-unsigned-rpm "${RPM_FILES[@]}"
fi
shopt -u nullglob
rm -rf "$RPM_DIR"


# ==========================================================
# 4. WIRTUALIZACJA I FIREWALL
# ==========================================================
log_info "Konfiguracja wirtualizacji i firewalla..."

QEMU_PKG=""
for candidate in qemu-kvm qemu-x86 qemu; do
    if sudo zypper search -x "$candidate" 2>/dev/null | grep -q "^i\|^v"; then
        QEMU_PKG="$candidate"
        break
    fi
done
[[ -z "$QEMU_PKG" ]] && QEMU_PKG="qemu-x86"

OVMF_PKG=""
for candidate in ovmf edk2-ovmf; do
    if sudo zypper search -x "$candidate" 2>/dev/null | grep -q "^i\|^v"; then
        OVMF_PKG="$candidate"
        break
    fi
done

sudo zypper install -y --allow-vendor-change virt-manager "$QEMU_PKG" qemu-tools libvirt libvirt-daemon-qemu "$OVMF_PKG" \
    || log_warn "Część pakietów wirtualizacji nie powiodła się — kontynuuję"

for svc in libvirtd virtqemud; do
    if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "$svc"; then
        sudo systemctl enable --now "${svc}.service"
        log_ok "Uruchomiono serwis: $svc"
        break
    fi
done

# Upewnij się, że sieć "default" (NAT dla maszyn wirtualnych) istnieje i wystartuje przy boocie
if ! sudo virsh net-info default &>/dev/null; then
    log_warn "Sieć 'default' nie jest zdefiniowana - definiuję z domyślnego XML..."
    sudo virsh net-define /usr/share/libvirt/networks/default.xml || true
fi
sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default || log_warn "Nie udało się ustawić autostartu sieci 'default' - sprawdź 'virsh net-list --all'."

# Konfiguracja firewalld PO starcie libvirtd, żeby interfejs virbr0 już istniał
if command -v firewall-cmd &>/dev/null; then
    sudo systemctl enable --now firewalld
    sudo firewall-cmd --permanent --zone=libvirt --add-interface=virbr0 2>/dev/null || true
    sudo firewall-cmd --permanent --add-source=192.168.122.0/24
    sudo firewall-cmd --reload
    log_ok "firewalld skonfigurowany"
fi

# Uzupełnienie grup (niezbędne do pracy bez roota)
for grp in libvirt kvm; do
    if getent group "$grp" &>/dev/null; then
        sudo usermod -aG "$grp" "$CURRENT_USER" \
            && log_ok "Dodano $CURRENT_USER do grupy $grp"
    fi
done


# ==========================================================
# 5. FINALIZACJA I OPTYMALIZACJA
# ==========================================================
log_info "Finalizacja i optymalizacja..."
mkdir -p ~/.config
if [[ -f ~/.config/kwalletrc ]]; then
    if grep -q "^\[Wallet\]" ~/.config/kwalletrc; then
        sed -i '/^\[Wallet\]/,/^\[/{s/^Enabled=.*/Enabled=false/}' ~/.config/kwalletrc
        grep -q "^Enabled=" ~/.config/kwalletrc || sed -i '/^\[Wallet\]/a Enabled=false' ~/.config/kwalletrc
    else
        printf '[Wallet]\nEnabled=false\n' >> ~/.config/kwalletrc
    fi
else
    printf '[Wallet]\nEnabled=false\n' > ~/.config/kwalletrc
fi

# Konfiguracja bleachbit
if [[ -d "$SCRIPT_DIR/bleachbit" ]]; then
    sudo mkdir -p /root/.config/bleachbit
    sudo cp -af "$SCRIPT_DIR/bleachbit/." /root/.config/bleachbit/
    log_ok "Skopiowano konfigurację BleachBit"
fi

sudo systemctl enable fstrim.timer || true
sudo journalctl --vacuum-time=2d || true

# Konfiguracja Loadera (systemd-boot)
LOADER_CONF="/boot/efi/loader/loader.conf"
if sudo test -f "$LOADER_CONF"; then
    if sudo grep -q "^#\?timeout" "$LOADER_CONF"; then
        sudo sed -i -E 's/^#?[[:space:]]*timeout[[:space:]].*/timeout 0/' "$LOADER_CONF"
    else
        echo "timeout 0" | sudo tee -a "$LOADER_CONF" > /dev/null
    fi
    if command -v bootctl >/dev/null 2>&1; then
        sudo bootctl set-timeout 0 || true
    fi
    log_ok "Ukryto menu systemd-boot"
fi

# DNS przez NetworkManager
ACTIVE_CONN=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep -v "^lo" | head -n 1 | cut -d: -f1 || true)
if [[ -n "$ACTIVE_CONN" ]]; then
    sudo nmcli connection modify "$ACTIVE_CONN" ipv4.dns "1.1.1.1,1.0.0.1" ipv6.dns "2606:4700:4700::1112,2606:4700:4700::1002"
    sudo nmcli connection up "$ACTIVE_CONN" || true
fi

# Konfiguracja ZSH
log_info "Konfiguracja ZSH..."
ZSH_BIN=$(command -v zsh || true)
if [[ -z "$ZSH_BIN" ]]; then
    sudo zypper install -y zsh && ZSH_BIN=$(command -v zsh || true)
fi

if [[ -n "$ZSH_BIN" ]]; then
    sudo chsh -s "$ZSH_BIN" "$CURRENT_USER"
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
    fi
    P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$P10K_DIR" ]]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" || true
    fi

    # zsh-autosuggestions i zsh-syntax-highlighting nie są dostępne w
    # oficjalnych repozytoriach Tumbleweed (tylko w osobnym repo OBS), więc
    # doinstalowujemy je jako pluginy oh-my-zsh przez git, analogicznie do p10k.
    ZSH_CUSTOM_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    AUTOSUGGESTIONS_DIR="$ZSH_CUSTOM_DIR/plugins/zsh-autosuggestions"
    if [[ ! -d "$AUTOSUGGESTIONS_DIR" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$AUTOSUGGESTIONS_DIR" || true
    fi
    SYNTAX_HIGHLIGHT_DIR="$ZSH_CUSTOM_DIR/plugins/zsh-syntax-highlighting"
    if [[ ! -d "$SYNTAX_HIGHLIGHT_DIR" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$SYNTAX_HIGHLIGHT_DIR" || true
    fi

    ZSHRC="$HOME/.zshrc"
    if [[ -f "$ZSHRC" ]]; then
        sed -i 's|^ZSH_THEME=.*|ZSH_THEME="powerlevel10k/powerlevel10k"|' "$ZSHRC"
        sed -i 's/^plugins=(.*/plugins=(git sudo systemd suse zsh-autosuggestions zsh-syntax-highlighting)/' "$ZSHRC"
        grep -q "LC_ALL=pl_PL.UTF-8" "$ZSHRC" || echo "export LC_ALL=pl_PL.UTF-8" >> "$ZSHRC"
        grep -q "^fastfetch"          "$ZSHRC" || echo "fastfetch"                  >> "$ZSHRC"
    fi
fi

# ── Sprzątanie wyjątków sudo ──────────────────────────────────
sudo rm -f /etc/sudoers.d/99-temp-installer

log_ok "KONFIGURACJA ZAKOŃCZONA SUKCESEM!"
sleep 3
systemctl reboot
