#!/bin/bash

# ==========================================================
# KOMPLEKSOWY SKRYPT KONFIGURACYJNY SYSTEMU openSUSE TUMBLEWEED
# ==========================================================

set -euo pipefail
export ZYPPER_NONINTERACTIVE=1

# ── Wykrywanie języka systemu ──────────────────────────────────
# Jeśli system jest ustawiony na polski (pl_PL/pl_*) -> komunikaty PL,
# w każdym innym przypadku -> komunikaty EN.
detect_system_lang() {
    local sys_lang="${LANG:-}"
    [[ -z "$sys_lang" ]] && sys_lang="${LC_ALL:-${LC_MESSAGES:-}}"
    if [[ "$sys_lang" == pl_PL* || "$sys_lang" == pl* ]]; then
        echo "pl"
    else
        echo "en"
    fi
}
SCRIPT_LANG="$(detect_system_lang)"

# ── Kolory ────────────────────────────────────────────────────
INFO='\033[0;34m'
SUCCESS='\033[0;32m'
WARN='\033[0;33m'
ERR='\033[0;31m'
NC='\033[0m'

# ── System logowania ───────────────────────────────────────────
# Zasada: na ekranie widoczne są TYLKO ważne komunikaty ogólne (log_info / log_ok / log_error).
# Wszystko inne (log_warn, wyjście poleceń, zypper, rpm itp.) trafia WYŁĄCZNIE do pliku logu.
# Plik logu jest tworzony na stałe tylko wtedy, gdy wystąpi błąd.
TMP_LOG="$(mktemp /tmp/opensuse-install-log.XXXXXX)"
LOG_FILE="$HOME/install_error_$(date +%Y%m%d_%H%M%S).log"

# fd 3 = prawdziwy terminal (do wyświetlania ważnych komunikatów),
# fd 1/2 od teraz lądują wyłącznie w pliku tymczasowym (ukryte).
exec 3>&1
exec >>"$TMP_LOG" 2>&1

cleanup_on_exit() {
    local exit_code=$?
    if [ "$exit_code" -ne 0 ]; then
        cp -f "$TMP_LOG" "$LOG_FILE" 2>/dev/null || true
        if [[ "$SCRIPT_LANG" == "pl" ]]; then
            echo -e "${ERR}✘ Wystąpił błąd (kod: $exit_code). Szczegółowy log zapisano w: $LOG_FILE${NC}" >&3
        else
            echo -e "${ERR}✘ An error occurred (code: $exit_code). Detailed log saved to: $LOG_FILE${NC}" >&3
        fi
    fi
    rm -f "$TMP_LOG"
}
trap cleanup_on_exit EXIT

# ── Pomocnicze funkcje logowania ──────────────────────────────
# Każda funkcja przyjmuje: "$1" = tekst PL, "$2" = tekst EN
_pick_msg() { [[ "$SCRIPT_LANG" == "pl" ]] && echo "$1" || echo "$2"; }

log_info()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${INFO}==> $m${NC}" >&3; echo -e "${INFO}==> $m${NC}"; }
log_ok()    { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${SUCCESS}✔ $m${NC}" >&3; echo -e "${SUCCESS}✔ $m${NC}"; }
log_error() { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${ERR}✘ $m${NC}" >&3; echo -e "${ERR}✘ $m${NC}"; }
# log_warn: celowo NIE trafia na ekran (fd 3) - tylko do logu w tle
log_warn()  { local m; m="$(_pick_msg "$1" "$2")"; echo -e "${WARN}⚠ $m${NC}"; }

# Upewnij się, że skrypt NIE jest uruchamiany jako root
if [[ "$EUID" -eq 0 ]]; then
    log_error "Nie uruchamiaj skryptu jako root. Uruchom jako zwykły użytkownik z uprawnieniami sudo." \
              "Do not run this script as root. Run as a regular user with sudo privileges."
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
    log_ok "Skopiowano katalog '.local' do \$HOME" \
           "Copied '.local' directory to \$HOME"
else
    log_warn "Brak katalogu '.local' w katalogu skryptu – pominięto" \
             "No '.local' directory in script folder – skipped"
fi

if [[ -d "$SCRIPT_DIR/.config" ]]; then
    mkdir -p ~/.config
    cp -afT "$SCRIPT_DIR/.config" ~/.config
    log_ok "Skopiowano katalog '.config' do \$HOME" \
           "Copied '.config' directory to \$HOME"
else
    log_warn "Brak katalogu '.config' w katalogu skryptu – pominięto" \
             "No '.config' directory in script folder – skipped"
fi

# ==========================================================
# 1. KONFIGURACJA SYSTEMOWA (SUDO)
# ==========================================================
log_info "Przechodzę do konfiguracji systemowej (openSUSE Tumbleweed)..." \
         "Starting system configuration (openSUSE Tumbleweed)..."

# Wyłączenie PackageKit, aby uniknąć problemów z blokadą bazy Zypper
log_info "Zatrzymywanie usług w tle (PackageKit)..." \
         "Stopping background services (PackageKit)..."
sudo systemctl stop packagekit.service 2>/dev/null || true
sudo killall -9 packagekitd 2>/dev/null || true

# Wczesna instalacja krytycznych zależności do działania skryptu
log_info "Instalacja podstawowych zależności (curl, wget, pciutils)..." \
         "Installing basic dependencies (curl, wget, pciutils)..."
sudo zypper install -y curl wget pciutils

# --- Dodanie repozytoriów ---

# Packman (kodeki, Wine staging, itp.)
log_info "Dodawanie repozytorium Packman..." \
         "Adding Packman repository..."
sudo zypper addrepo -cfp 90 https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/ packman \
    || log_warn "Repozytorium Packman już dodane" "Packman repository already added"
sudo rpm --import https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Tumbleweed/repodata/repomd.xml.key 2>/dev/null || true

# Repozytorium games (gamemode, mangohud, gamescope)
log_info "Dodawanie repozytorium games..." \
         "Adding games repository..."
sudo zypper addrepo -cfp 80 https://download.opensuse.org/repositories/games/openSUSE_Tumbleweed/ games \
    || log_warn "Repozytorium games już dodane" "Games repository already added"

# Repozytorium Emulators
log_info "Dodawanie repozytorium emulators..." \
         "Adding emulators repository..."
sudo zypper addrepo -cfp 80 https://download.opensuse.org/repositories/Emulators/openSUSE_Tumbleweed/ emulators \
    || log_warn "Repozytorium Emulators już dodane" "Emulators repository already added"

# Repozytorium Emulators:Wine (dla najnowszego Wine)
log_info "Dodawanie repozytorium Emulators:Wine..." \
         "Adding Emulators:Wine repository..."
sudo zypper addrepo -cfp 80 https://download.opensuse.org/repositories/Emulators:/Wine/openSUSE_Tumbleweed/ emulators-wine \
    || log_warn "Repozytorium Emulators:Wine już dodane" "Emulators:Wine repository already added"

# Google Chrome
log_info "Dodawanie repozytorium Google Chrome..." \
         "Adding Google Chrome repository..."
sudo zypper addrepo -cfp 80 https://dl.google.com/linux/chrome/rpm/stable/x86_64 google-chrome \
    || log_warn "Repozytorium Google Chrome już dodane" "Google Chrome repository already added"
sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub 2>/dev/null || true

# Brave (Origin)
log_info "Dodawanie repozytorium Brave Origin..." \
         "Adding Brave Origin repository..."

sudo zypper install -y gpg2 2>/dev/null || true
BRAVE_KEY_ID="0686B78420038257"
if ! sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc 2>/dev/null; then
    log_warn "Import klucza Brave z brave-core.asc nie powiódł się, próbuję keyservera..." \
             "Brave key import from brave-core.asc failed, trying keyserver..."

    KEY_FETCHED=true
    if ! gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keyserver.ubuntu.com --recv-keys "$BRAVE_KEY_ID"; then
        log_warn "keyserver.ubuntu.com nie odpowiedział, próbuję keys.openpgp.org..." \
                 "keyserver.ubuntu.com did not respond, trying keys.openpgp.org..."

        if ! gpg --homedir "$BRAVE_GNUPGHOME" --keyserver hkps://keys.openpgp.org --recv-keys "$BRAVE_KEY_ID"; then
            log_warn "Nie udało się pobrać klucza Brave z żadnego serwera (keys.openpgp.org również zawiódł)." \
                     "Failed to fetch Brave GPG key from any server."
            KEY_FETCHED=false
        fi
    fi

    # Eksportuj i importuj TYLKO wtedy, gdy pobieranie się udało
    if [ "$KEY_FETCHED" = true ]; then
        gpg --homedir "$BRAVE_GNUPGHOME" --armor --export "$BRAVE_KEY_ID" > "$BRAVE_GNUPGHOME/brave-core.asc" || true
        sudo rpm --import "$BRAVE_GNUPGHOME/brave-core.asc" || true
    fi

    rm -rf "$BRAVE_GNUPGHOME"
fi

sudo zypper addrepo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo \
    || log_warn "Repozytorium Brave już dodane" "Brave repository already added"

# Odśwież repozytoria
log_info "Odświeżanie repozytoriów..." \
         "Refreshing repositories..."
sudo zypper --gpg-auto-import-keys refresh

# Aktualizacja systemu
log_info "Aktualizacja systemu (dup)..." \
         "Updating system (dup)..."
sudo zypper dup -y --allow-vendor-change

# --- Przeglądarki ---
log_info "Instalacja przeglądarek..." \
         "Installing browsers..."
sudo zypper install -y google-chrome-stable || log_warn "Instalacja Chrome nie powiodła się" "Chrome installation failed"
sudo zypper install -y brave-origin || log_warn "Instalacja Brave nie powiodła się" "Brave installation failed"

# --- Czyszczenie zbędnych pakietów ---
log_info "Usuwanie zbędnych pakietów..." \
         "Removing unnecessary packages..."
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
            && log_ok "Usunięto: $pkg" "Removed: $pkg" \
            || log_warn "Nie udało się usunąć: $pkg — pomijam" "Failed to remove: $pkg — skipping"
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

log_info "Instalacja głównej listy pakietów 64-bit..." \
         "Installing main 64-bit package list..."
for pkg in "${PACKAGES[@]}"; do
    if sudo zypper install -y --allow-vendor-change "$pkg" 2>/dev/null; then
        continue
    fi
    if sudo zypper install -y --allow-vendor-change --from packman "$pkg" 2>/dev/null; then
        log_ok "Zainstalowano z Packman: $pkg" "Installed from Packman: $pkg"
    else
        log_warn "Pominięto pakiet: $pkg (niedostępny)" "Skipped package: $pkg (unavailable)"
    fi
done

log_info "Instalacja opcjonalnych pakietów..." \
         "Installing optional packages..."
for pkg in "${OPTIONAL_PACKAGES[@]}"; do
    sudo zypper install -y --allow-vendor-change "$pkg" 2>/dev/null \
        && log_ok "Zainstalowano: $pkg" "Installed: $pkg" \
        || log_warn "Pakiet $pkg niedostępny — pomijam" "Package $pkg unavailable — skipping"
done


# ==========================================================
# 2. WYKRYWANIE GPU: BIBLIOTEKI 32-BIT I DRACUT (EARLY KMS)
# ==========================================================
log_info "Wykrywanie sprzętu w celu instalacji bibliotek 32-bitowych i konfiguracji dracut (Early KMS)..." \
         "Detecting hardware for 32-bit libraries and dracut configuration (Early KMS)..."

PACKAGES_32=(
    mangohud-32bit libgamemodeauto0-32bit libvkd3d1-32bit wine-staging-32bit
    libopenal1-32bit libXdamage1-32bit libXtst6-32bit
    libgtk-2_0-0-32bit libgtk-3-0-32bit
)

GPU_VENDOR=$(lspci -nn | grep -iE "VGA|3D|Display" || true)
DRACUT_CONF="/etc/dracut.conf.d/90-gpu.conf"

if echo "$GPU_VENDOR" | grep -iq "nvidia"; then
    log_ok "Wykryto układ NVIDIA. Dodaję biblioteki GLVND oraz moduły dracut..." \
           "NVIDIA GPU detected. Adding GLVND libraries and dracut modules..."
    PACKAGES_32+=(libglvnd-32bit)
    echo 'force_drivers+=" nvidia nvidia_modeset nvidia_uvm nvidia_drm "' | sudo tee "$DRACUT_CONF" > /dev/null

elif echo "$GPU_VENDOR" | grep -iqE "amd|radeon"; then
    log_ok "Wykryto układ AMD. Dodaję biblioteki Mesa oraz moduł amdgpu..." \
           "AMD GPU detected. Adding Mesa libraries and amdgpu module..."
    PACKAGES_32+=(libvulkan_radeon-32bit)
    echo 'force_drivers+=" amdgpu "' | sudo tee "$DRACUT_CONF" > /dev/null

elif echo "$GPU_VENDOR" | grep -iq "intel"; then
    log_ok "Wykryto układ Intel. Dodaję biblioteki Mesa oraz moduł i915..." \
           "Intel GPU detected. Adding Mesa libraries and i915 module..."
    PACKAGES_32+=(libvulkan_intel-32bit)
    echo 'force_drivers+=" i915 "' | sudo tee "$DRACUT_CONF" > /dev/null

else
    log_warn "Nie udało się jednoznacznie wykryć GPU. Używam ustawień generycznych." \
             "Failed to unambiguously detect GPU. Using generic settings."
    sudo rm -f "$DRACUT_CONF"
fi

log_info "Instalacja bibliotek 32-bitowych..." \
         "Installing 32-bit libraries..."
for pkg in "${PACKAGES_32[@]}"; do
    sudo zypper install -y --allow-vendor-change "$pkg" 2>/dev/null || log_warn "Pominięto 32-bit: $pkg" "Skipped 32-bit: $pkg"
done

log_info "Instalacja opcjonalnych bibliotek 32-bitowych..." \
         "Installing optional 32-bit libraries..."
for pkg in "${PACKAGES_32_OPTIONAL[@]}"; do
    sudo zypper install -y --allow-vendor-change "$pkg" 2>/dev/null || log_warn "Pakiet $pkg niedostępny — pomijam" "Package $pkg unavailable — skipping"
done

if [[ -f "$DRACUT_CONF" ]]; then
    log_info "Przebudowa obrazu initramfs (dracut) dla wczesnego KMS..." \
             "Rebuilding initramfs image (dracut) for early KMS..."
    sudo dracut --force
fi


# ==========================================================
# 3. PAKIETY RPM POBIERANE RĘCZNIE I FLATPAK
# ==========================================================
log_info "Pobieranie i instalacja zewnętrznych pakietów..." \
         "Downloading and installing external packages..."

download_rpm() {
    local name="$1" url="$2" dest="$3"
    if wget -q --timeout=30 -O "$dest" "$url"; then
        log_ok "Pobrano: $name" "Downloaded: $name"
    else
        log_warn "Nie udało się pobrać: $name ($url) — pomijam" "Failed to download: $name ($url) — skipping"
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
            log_error "Pobrany plik nie jest poprawną paczką RPM. Discord blokuje pobieranie." \
                      "Downloaded file is not a valid RPM package. Discord blocks download."
            rm -f "$dest"
        fi
    else
        log_warn "Nie udało się połączyć z serwerem Discord." "Failed to connect to Discord server."
    fi
}

# Discord
if sudo zypper repos | grep -iq "packman"; then
    sudo zypper install -y discord \
        && log_ok "Discord zainstalowany z repozytorium Packman." "Discord installed from Packman repository." \
        || { log_warn "Błąd instalacji Discorda. Próbuję pobrać RPM ręcznie..." "Discord installation error. Attempting manual RPM download..."; install_discord_rpm; }
else
    log_warn "Repozytorium Packman niewykryte. Próbuję pobrać RPM ręcznie..." "Packman repository not detected. Attempting manual RPM download..."
    install_discord_rpm
fi

# ls-fg i ls-fg-vk (GitHub)
LSFG_URL=$(curl -sf https://api.github.com/repos/YuriSizov/ls-fg/releases/latest | grep "browser_download_url.*ls-fg_.*rpm" | cut -d '"' -f 4 || true)
[[ -n "$LSFG_URL" ]] && download_rpm "ls-fg" "$LSFG_URL" "$RPM_DIR/lsfg.rpm"

LSFG_VK_URL=$(curl -sf https://api.github.com/repos/YuriSizov/ls-fg-vk/releases/latest | grep "browser_download_url.*rpm" | cut -d '"' -f 4 || true)
[[ -n "$LSFG_VK_URL" ]] && download_rpm "ls-fg-vk" "$LSFG_VK_URL" "$RPM_DIR/lsfg-vk.rpm"

# Faugus Launcher (GitHub)
log_info "Instalacja Faugus Launcher (GitHub)..." \
         "Installing Faugus Launcher (GitHub)..."
sudo zypper install -y --allow-vendor-change \
    python3-gobject python3-Pillow python3-psutil python3-requests \
    libcanberra-gtk3-module vulkan-tools ImageMagick 2>/dev/null \
    || log_warn "Część zależności Faugus Launcher niedostępna w repozytoriach — kontynuuję" "Some Faugus Launcher dependencies unavailable in repositories — continuing"

sudo pip3 install --break-system-packages -q vdf icoextract pygame 2>/dev/null \
    || log_warn "Nie udało się doinstalować modułów pip dla Faugus Launcher (vdf/icoextract/pygame)" "Failed to install pip modules for Faugus Launcher (vdf/icoextract/pygame)"

FAUGUS_URL=$(curl -sf https://api.github.com/repos/Faugus/faugus-launcher/releases/latest \
    | grep "browser_download_url.*noarch.rpm" | cut -d '"' -f 4 || true)

if [[ -n "$FAUGUS_URL" ]]; then
    FAUGUS_RPM="$RPM_DIR/faugus-launcher-standalone.rpm"
    download_rpm "faugus-launcher" "$FAUGUS_URL" "$FAUGUS_RPM"
    if [[ -f "$FAUGUS_RPM" ]]; then
        sudo rpm -Uvh --nodeps --force "$FAUGUS_RPM" \
            && log_ok "Zainstalowano Faugus Launcher" "Faugus Launcher installed" \
            || log_warn "Instalacja Faugus Launcher nie powiodła się" "Faugus Launcher installation failed"
        rm -f "$FAUGUS_RPM"
    fi
else
    log_warn "Nie udało się znaleźć pakietu RPM Faugus Launcher na GitHub — pomijam" "Failed to find Faugus Launcher RPM on GitHub — skipping"
fi

# Flathub (repozytorium Flatpak)
log_info "Dodawanie repozytorium Flathub..." \
         "Adding Flathub repository..."
sudo zypper install -y flatpak 2>/dev/null || true
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo \
    && log_ok "Repozytorium Flathub dodane" "Flathub repository added" \
    || log_warn "Nie udało się dodać repozytorium Flathub" "Failed to add Flathub repository"

log_info "Odświeżanie metadanych Flathub..." \
         "Refreshing Flathub metadata..."
flatpak update --appstream 2>/dev/null || log_warn "Nie udało się odświeżyć metadanych Flathub" "Failed to refresh Flathub metadata"

# Flatseal (Flatpak)
flatpak install --user -y flathub com.github.tchx84.Flatseal 2>/dev/null \
    || log_warn "Instalacja Flatseal nie powiodła się — pomijam" "Flatseal installation failed — skipping"

# Gear Lever (Flatpak)
flatpak install --user -y flathub it.mijorus.gearlever 2>/dev/null \
    || log_warn "Instalacja Gear Lever nie powiodła się — pomijam" "Gear Lever installation failed — skipping"

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
log_info "Konfiguracja wirtualizacji i firewalla..." \
         "Configuring virtualization and firewall..."

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
    || log_warn "Część pakietów wirtualizacji nie powiodła się — kontynuuję" "Some virtualization packages failed — continuing"

for svc in libvirtd virtqemud; do
    if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "$svc"; then
        sudo systemctl enable --now "${svc}.service"
        log_ok "Uruchomiono serwis: $svc" "Service started: $svc"
        break
    fi
done

# Upewnij się, że sieć "default" (NAT dla maszyn wirtualnych) istnieje i wystartuje przy boocie
if ! sudo virsh net-info default &>/dev/null; then
    log_warn "Sieć 'default' nie jest zdefiniowana - definiuję z domyślnego XML..." \
             "'default' network not defined - defining from default XML..."
    sudo virsh net-define /usr/share/libvirt/networks/default.xml || true
fi
sudo virsh net-start default 2>/dev/null || true
sudo virsh net-autostart default || log_warn "Nie udało się ustawić autostartu sieci 'default' - sprawdź 'virsh net-list --all'." "Failed to set autostart for 'default' network - check 'virsh net-list --all'."

# Konfiguracja firewalld PO starcie libvirtd, żeby interfejs virbr0 już istniał
if command -v firewall-cmd &>/dev/null; then
    sudo systemctl enable --now firewalld
    sudo firewall-cmd --permanent --zone=libvirt --add-interface=virbr0 2>/dev/null || true
    sudo firewall-cmd --permanent --add-source=192.168.122.0/24
    sudo firewall-cmd --reload
    log_ok "firewalld skonfigurowany" "firewalld configured"
fi

# Uzupełnienie grup (niezbędne do pracy bez roota)
for grp in libvirt kvm; do
    if getent group "$grp" &>/dev/null; then
        sudo usermod -aG "$grp" "$CURRENT_USER" \
            && log_ok "Dodano $CURRENT_USER do grupy $grp" "Added $CURRENT_USER to group $grp"
    fi
done


# ==========================================================
# 5. FINALIZACJA I OPTYMALIZACJA
# ==========================================================
log_info "Finalizacja i optymalizacja..." \
         "Finalization and optimization..."
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
    log_ok "Ukryto menu systemd-boot" "Systemd-boot menu hidden"
fi

# DNS przez NetworkManager
ACTIVE_CONN=$(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | grep -v "^lo" | head -n 1 | cut -d: -f1 || true)
if [[ -n "$ACTIVE_CONN" ]]; then
    sudo nmcli connection modify "$ACTIVE_CONN" ipv4.dns "1.1.1.1,1.0.0.1" ipv6.dns "2606:4700:4700::1112,2606:4700:4700::1002"
    sudo nmcli connection up "$ACTIVE_CONN" || true
fi

# Konfiguracja ZSH
log_info "Konfiguracja ZSH..." \
         "Configuring ZSH..."
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

log_ok "KONFIGURACJA ZAKOŃCZONA SUKCESEM!" \
       "CONFIGURATION COMPLETED SUCCESSFULLY!"
systemctl reboot
