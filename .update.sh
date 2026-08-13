#!/bin/bash

# Kolory dla lepszej czytelności / Colors for better readability
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# =========================================================
# WYKRYWANIE JĘZYKA SYSTEMU / SYSTEM LANGUAGE DETECTION
# =========================================================
DETECTED_LOCALE="${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}"
if [ -z "$DETECTED_LOCALE" ] && command -v locale &> /dev/null; then
    DETECTED_LOCALE=$(locale 2>/dev/null | grep -m1 '^LANG=' | cut -d= -f2)
fi

if [[ "$DETECTED_LOCALE" == pl_PL* ]] || [[ "$DETECTED_LOCALE" == pl* ]]; then
    IS_PL=true
else
    IS_PL=false
fi

# =========================================================
# KOMUNIKATY / MESSAGES
# =========================================================
if [ "$IS_PL" = true ]; then
    MSG_TITLE="       KOMPLEKSOWY SKRYPT AKTUALIZACJI I CZYSZCZENIA  "
    MSG_ASK_PASS="Proszę podać hasło administratora (sudo):"
    MSG_UNKNOWN_OS="Nieznany"
    MSG_UNKNOWN_OS_WARN="Ostrzeżenie: Wykryto system inny niż Tumbleweed lub Leap. Zastosowana zostanie bezpieczna aktualizacja (up)."
    MSG_PHASE1_TITLE="   FAZA 1: SYSTEM (SUDO)                              "
    MSG_DUP_TUMBLEWEED="==> Wykryto openSUSE Tumbleweed. Wykonuję 'zypper dup'..."
    MSG_UP_OTHER="==> Wykryto openSUSE \$OS_NAME. Wykonuję 'zypper up'..."
    MSG_FWUPD_REFRESH="==> Odświeżanie metadanych firmware (fwupd)..."
    MSG_FWUPD_UPDATE="==> Sprawdzanie i instalowanie aktualizacji firmware (fwupd)..."
    MSG_FWUPD_ABSENT="==> fwupdmgr nieobecny w systemie - pomijam aktualizację firmware."
    MSG_FWUPD_RESTART_NEEDED="UWAGA: Zainstalowano aktualizację firmware wymagającą restartu!"
    MSG_CHECK_ORPHANS="==> Sprawdzanie osieroconych pakietów (orphans)..."
    MSG_FOUND_ORPHANS="Znaleziono potencjalnie nieużywane pakiety:"
    MSG_ORPHAN_WARN1="UWAGA: Automatyczne usuwanie tych pakietów może uszkodzić system."
    MSG_ORPHAN_WARN2="Przejrzyj listę i usuń ręcznie tylko te, które na pewno są zbędne:"
    MSG_ORPHAN_CONFIRM_PROMPT="Czy chcesz usunąć wszystkie powyższe pakiety? (wpisz 'TAK' aby potwierdzić): "
    MSG_ORPHAN_CONFIRM_WORD="TAK"
    MSG_REMOVING_ORPHANS="==> Usuwanie osieroconych pakietów..."
    MSG_SKIPPED_ORPHANS="==> Pominięto usuwanie osieroconych pakietów."
    MSG_NO_ORPHANS="Brak osieroconych pakietów."
    MSG_REMOVE_UNUSED_REPOS="==> Usuwanie nieużywanych repozytoriów Zypper..."
    MSG_NO_INACTIVE_REPOS="Brak nieaktywnych repozytoriów."
    MSG_CLEAN_ZYPPER_CACHE="==> Czyszczenie cache pobierania Zyppera..."
    MSG_FLATPAK_UPDATE_SYS="==> Aktualizacja systemowych pakietów Flatpak..."
    MSG_FLATPAK_CLEAN_SYS="==> Kompleksowe czyszczenie Flatpak (System)..."
    MSG_FLATPAK_REMOVING_REMOTE_SYS="Usuwanie systemowego repozytorium Flatpak:"
    MSG_FLATPAK_CLEAN_VARAPP_SYS="==> Czyszczenie osieroconych danych systemowych w /var/app..."
    MSG_REMOVING="Usuwanie:"
    MSG_CLEAN_LOGS="==> Czyszczenie starych logów (starsze niż 7 dni)..."
    MSG_PURGE_KERNELS="==> Czyszczenie starych kerneli..."
    MSG_CLEAN_TMP="==> Czyszczenie /tmp i /var/tmp (starsze niż 3 dni)..."
    MSG_PHASE2_TITLE="   FAZA 2: UŻYTKOWNIK (BEZ SUDO)                      "
    MSG_FLATPAK_UPDATE_USER="==> Aktualizacja pakietów Flatpak użytkownika..."
    MSG_FLATPAK_CLEAN_USER="==> Kompleksowe czyszczenie Flatpak (Użytkownik)..."
    MSG_FLATPAK_CLEAN_VARAPP_USER="==> Czyszczenie osieroconych danych w ~/.var/app..."
    MSG_CLEAN_THUMBS="==> Czyszczenie starych miniatur (starsze niż 7 dni)..."
    MSG_CLEAN_USER_CACHE="==> Czyszczenie starego cache użytkownika (omijanie przeglądarek)..."
    MSG_CLEAN_VIRT="==> Czyszczenie virt-manager i reset historii ISO..."
    MSG_REBUILD_FONTS="==> Odświeżanie cache czcionek..."
    MSG_PHASE3_TITLE="   FAZA 3: SPRAWDZANIE STANU SYSTEMU                  "
    MSG_CHECK_RESTART="==> Sprawdzanie konieczności restartu systemu (zypper ps)..."
    MSG_RESTART_WARN1="UWAGA: Zaktualizowano kluczowe pakiety (np. kernel)!"
    MSG_RESTART_WARN2=" ZALECANY JEST RESTART KOMPUTERA!                     "
    MSG_NO_RESTART_NEEDED="==> Restart systemu nie jest aktualnie wymagany."
    MSG_DONE_TITLE="       AKTUALIZACJA I CZYSZCZENIE ZAKOŃCZONE!          "
    MSG_PRESS_ENTER="Naciśnij [ENTER], aby zakończyć..."
else
    MSG_TITLE="         COMPREHENSIVE UPDATE AND CLEANUP SCRIPT       "
    MSG_ASK_PASS="Please enter the administrator (sudo) password:"
    MSG_UNKNOWN_OS="Unknown"
    MSG_UNKNOWN_OS_WARN="Warning: Detected a system other than Tumbleweed or Leap. A safe update (up) will be used."
    MSG_PHASE1_TITLE="   PHASE 1: SYSTEM (SUDO)                             "
    MSG_DUP_TUMBLEWEED="==> Detected openSUSE Tumbleweed. Running 'zypper dup'..."
    MSG_UP_OTHER="==> Detected openSUSE \$OS_NAME. Running 'zypper up'..."
    MSG_FWUPD_REFRESH="==> Refreshing firmware metadata (fwupd)..."
    MSG_FWUPD_UPDATE="==> Checking for and installing firmware updates (fwupd)..."
    MSG_FWUPD_ABSENT="==> fwupdmgr not present on the system - skipping firmware update."
    MSG_FWUPD_RESTART_NEEDED="WARNING: A firmware update requiring a restart was installed!"
    MSG_CHECK_ORPHANS="==> Checking for orphaned packages..."
    MSG_FOUND_ORPHANS="Found potentially unused packages:"
    MSG_ORPHAN_WARN1="WARNING: Automatically removing these packages could break the system."
    MSG_ORPHAN_WARN2="Review the list and manually remove only those you're sure are unnecessary:"
    MSG_ORPHAN_CONFIRM_PROMPT="Do you want to remove all the packages above? (type 'YES' to confirm): "
    MSG_ORPHAN_CONFIRM_WORD="YES"
    MSG_REMOVING_ORPHANS="==> Removing orphaned packages..."
    MSG_SKIPPED_ORPHANS="==> Skipped removing orphaned packages."
    MSG_NO_ORPHANS="No orphaned packages found."
    MSG_REMOVE_UNUSED_REPOS="==> Removing unused Zypper repositories..."
    MSG_NO_INACTIVE_REPOS="No inactive repositories found."
    MSG_CLEAN_ZYPPER_CACHE="==> Cleaning the Zypper download cache..."
    MSG_FLATPAK_UPDATE_SYS="==> Updating system Flatpak packages..."
    MSG_FLATPAK_CLEAN_SYS="==> Comprehensive Flatpak cleanup (System)..."
    MSG_FLATPAK_REMOVING_REMOTE_SYS="Removing system Flatpak remote:"
    MSG_FLATPAK_CLEAN_VARAPP_SYS="==> Cleaning orphaned system data in /var/app..."
    MSG_REMOVING="Removing:"
    MSG_CLEAN_LOGS="==> Cleaning old logs (older than 7 days)..."
    MSG_PURGE_KERNELS="==> Cleaning old kernels..."
    MSG_CLEAN_TMP="==> Cleaning /tmp and /var/tmp (older than 3 days)..."
    MSG_PHASE2_TITLE="   PHASE 2: USER (NO SUDO)                            "
    MSG_FLATPAK_UPDATE_USER="==> Updating user Flatpak packages..."
    MSG_FLATPAK_CLEAN_USER="==> Comprehensive Flatpak cleanup (User)..."
    MSG_FLATPAK_CLEAN_VARAPP_USER="==> Cleaning orphaned data in ~/.var/app..."
    MSG_CLEAN_THUMBS="==> Cleaning old thumbnails (older than 7 days)..."
    MSG_CLEAN_USER_CACHE="==> Cleaning old user cache (skipping browsers)..."
    MSG_CLEAN_VIRT="==> Cleaning virt-manager and resetting ISO history..."
    MSG_REBUILD_FONTS="==> Refreshing font cache..."
    MSG_PHASE3_TITLE="   PHASE 3: CHECKING SYSTEM STATE                     "
    MSG_CHECK_RESTART="==> Checking if a system restart is needed (zypper ps)..."
    MSG_RESTART_WARN1="WARNING: Key packages have been updated (e.g. kernel)!"
    MSG_RESTART_WARN2=" A SYSTEM RESTART IS RECOMMENDED!                     "
    MSG_NO_RESTART_NEEDED="==> A system restart is not currently required."
    MSG_DONE_TITLE="       UPDATE AND CLEANUP COMPLETE!                    "
    MSG_PRESS_ENTER="Press [ENTER] to finish..."
fi

echo -e "${BLUE}======================================================${NC}"
echo -e "${BLUE}${MSG_TITLE}${NC}"
echo -e "${BLUE}======================================================${NC}"

# Zapytanie o hasło administratora (TYLKO RAZ) / Ask for the admin password (ONCE ONLY)
echo -e "${YELLOW}${MSG_ASK_PASS}${NC}"
sudo -v

# Utrzymanie aktywnej sesji sudo w tle / Keep the sudo session alive in the background
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEP_ALIVE_PID=$!
trap 'kill $SUDO_KEEP_ALIVE_PID 2>/dev/null' EXIT

# Rozpoznawanie konkretnej wersji openSUSE / Detecting the specific openSUSE version
OS_ID=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')

if [ "$OS_ID" == "opensuse-tumbleweed" ]; then
    OS_NAME="Tumbleweed"
elif [ "$OS_ID" == "opensuse-leap" ]; then
    OS_NAME="Leap"
else
    OS_NAME="$MSG_UNKNOWN_OS ($OS_ID)"
    echo -e "${YELLOW}${MSG_UNKNOWN_OS_WARN}${NC}"
fi

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}${MSG_PHASE1_TITLE}${NC}"
echo -e "${BLUE}======================================================${NC}"

# 1. Pełna aktualizacja systemu / Full system update
if [ "$OS_NAME" == "Tumbleweed" ]; then
    echo -e "${GREEN}${MSG_DUP_TUMBLEWEED}${NC}"
    sudo zypper dup --no-allow-vendor-change --auto-agree-with-licenses
else
    echo -e "${GREEN}${MSG_UP_OTHER//\$OS_NAME/$OS_NAME}${NC}"
    sudo zypper up --auto-agree-with-licenses
fi

# 1a. Aktualizacja firmware / Firmware update
FWUPD_RESTART_NEEDED=false
if command -v fwupdmgr &> /dev/null; then
    echo -e "${GREEN}${MSG_FWUPD_REFRESH}${NC}"
    sudo fwupdmgr refresh --force

    echo -e "${GREEN}${MSG_FWUPD_UPDATE}${NC}"
    FWUPD_OUT=$(sudo fwupdmgr update -y 2>&1)
    echo "$FWUPD_OUT"

    if echo "$FWUPD_OUT" | grep -qiE "restart|reboot"; then
        FWUPD_RESTART_NEEDED=true
    fi
else
    echo -e "${YELLOW}${MSG_FWUPD_ABSENT}${NC}"
fi

# 2. Czyszczenie osieroconych pakietów (bezpieczny tryb interaktywny) / Cleaning orphaned packages (safe interactive mode)
echo -e "${GREEN}${MSG_CHECK_ORPHANS}${NC}"
ORPHANS=$(zypper packages --unneeded | awk -F'|' 'NR>4 {gsub(/ /, "", $3); print $3}' | grep -v '^$')
if [ -n "$ORPHANS" ]; then
    echo -e "${YELLOW}${MSG_FOUND_ORPHANS}${NC}"
    echo "$ORPHANS" | nl -ba
    echo ""
    echo -e "${YELLOW}${MSG_ORPHAN_WARN1}${NC}"
    echo -e "${YELLOW}${MSG_ORPHAN_WARN2}${NC}"
    echo -e "${YELLOW}  sudo zypper rm NAZWA_PAKIETU${NC}"
    echo ""
    read -rp "$(echo -e "${YELLOW}${MSG_ORPHAN_CONFIRM_PROMPT}${NC}")" CONFIRM
    if [ "$CONFIRM" == "$MSG_ORPHAN_CONFIRM_WORD" ]; then
        echo -e "${GREEN}${MSG_REMOVING_ORPHANS}${NC}"
        # shellcheck disable=SC2086
        sudo zypper rm $ORPHANS
    else
        echo -e "${GREEN}${MSG_SKIPPED_ORPHANS}${NC}"
    fi
else
    echo "$MSG_NO_ORPHANS"
fi

# 3. Repozytoria i Cache Zyppera / Zypper repos and cache
echo -e "${GREEN}${MSG_REMOVE_UNUSED_REPOS}${NC}"
REPOS_TO_REMOVE=$(zypper lr | awk -F'|' '$4 ~ /No/ {print $2}' | xargs)
if [ -n "$REPOS_TO_REMOVE" ]; then
    for repo in $REPOS_TO_REMOVE; do sudo zypper rr "$repo"; done
else
    echo "$MSG_NO_INACTIVE_REPOS"
fi

echo -e "${GREEN}${MSG_CLEAN_ZYPPER_CACHE}${NC}"
sudo zypper clean -a

# 4. Aktualizacja i kompleksowe czyszczenie Flatpak (System) / Updating and cleaning up Flatpak (System)
if command -v flatpak &> /dev/null; then
    echo -e "${GREEN}${MSG_FLATPAK_UPDATE_SYS}${NC}"
    sudo flatpak update --system -y

    echo -e "${GREEN}${MSG_FLATPAK_CLEAN_SYS}${NC}"
    sudo flatpak uninstall --unused --system --delete-data -y
    sudo flatpak repair --system

    # Usuwanie nieużywanych źródeł (remotes) / Removing unused remotes
    USED_REMOTES=$(flatpak list --system --columns=origin 2>/dev/null | sort -u)
    ALL_REMOTES=$(flatpak remotes --system --columns=name 2>/dev/null | tail -n +1)

    while IFS= read -r remote; do
        if [ -n "$remote" ] && ! echo "$USED_REMOTES" | grep -qx "$remote"; then
            echo -e "${YELLOW}${MSG_FLATPAK_REMOVING_REMOTE_SYS} $remote${NC}"
            sudo flatpak remote-delete --system --force "$remote" 2>/dev/null
        fi
    done <<< "$ALL_REMOTES"

    # Czyszczenie śmieci Flatpak / Cleaning up Flatpak leftovers
    sudo rm -rf /var/tmp/flatpak-cache-* 2>/dev/null
    sudo find /var/lib/flatpak -name "*.tmp" -delete 2>/dev/null
    sudo rm -f /var/lib/flatpak/history 2>/dev/null

    # Inteligentne czyszczenie /var/app / Smart /var/app cleanup
    echo -e "${GREEN}${MSG_FLATPAK_CLEAN_VARAPP_SYS}${NC}"
    INSTALLED_FLATPAKS=$(flatpak list --app --columns=application 2>/dev/null)
    if [ -d "/var/app" ]; then
        for app_dir in /var/app/*; do
            if [ -d "$app_dir" ]; then
                app_id=$(basename "$app_dir")
                if ! echo "$INSTALLED_FLATPAKS" | grep -qx "$app_id"; then
                    echo -e "${YELLOW}${MSG_REMOVING} $app_id${NC}"
                    sudo rm -rf "$app_dir"
                fi
            fi
        done
    fi
fi

# 5. Logi, stare kernele i stare pliki tymczasowe / Logs, old kernels and old temp files
echo -e "${GREEN}${MSG_CLEAN_LOGS}${NC}"
sudo journalctl --vacuum-time=7d

echo -e "${GREEN}${MSG_PURGE_KERNELS}${NC}"
[ -f /sbin/purge-kernels ] && sudo /sbin/purge-kernels

echo -e "${GREEN}${MSG_CLEAN_TMP}${NC}"
sudo find /tmp -type f -atime +3 -delete 2>/dev/null
sudo find /var/tmp -type f -atime +3 -delete 2>/dev/null


echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}${MSG_PHASE2_TITLE}${NC}"
echo -e "${BLUE}======================================================${NC}"

# 1. Aktualizacja i kompleksowe czyszczenie Flatpak (Użytkownik) / Updating and cleaning up Flatpak (User)
if command -v flatpak &> /dev/null; then
    echo -e "${GREEN}${MSG_FLATPAK_UPDATE_USER}${NC}"
    flatpak update --user -y

    echo -e "${GREEN}${MSG_FLATPAK_CLEAN_USER}${NC}"
    flatpak uninstall --unused --user --delete-data -y
    flatpak repair --user

    # Czyszczenie historii i repozytoriów tymczasowych / Cleaning history and temp repos
    rm -f ~/.local/share/flatpak/history 2>/dev/null
    rm -rf ~/.local/share/flatpak/repo/tmp/* 2>/dev/null

    # Inteligentne czyszczenie ~/.var/app / Smart ~/.var/app cleanup
    echo -e "${GREEN}${MSG_FLATPAK_CLEAN_VARAPP_USER}${NC}"
    INSTALLED_FLATPAKS=$(flatpak list --app --columns=application 2>/dev/null)
    if [ -d "$HOME/.var/app" ]; then
        for app_dir in "$HOME/.var/app"/*; do
            if [ -d "$app_dir" ]; then
                app_id=$(basename "$app_dir")
                if ! echo "$INSTALLED_FLATPAKS" | grep -qx "$app_id"; then
                    echo -e "${YELLOW}${MSG_REMOVING} $app_id${NC}"
                    rm -rf "$app_dir"
                fi
            fi
        done
    fi
fi

# 2. Czyszczenie starych miniatur i cache / Cleaning old thumbnails and cache
echo -e "${GREEN}${MSG_CLEAN_THUMBS}${NC}"
find ~/.cache/thumbnails -type f -atime +7 -delete 2>/dev/null

echo -e "${GREEN}${MSG_CLEAN_USER_CACHE}${NC}"
find ~/.cache -type f -atime +14 \
    ! -path "*/mozilla/*" \
    ! -path "*/google-chrome/*" \
    ! -path "*/chromium/*" \
    ! -path "*/BraveSoftware/*" \
    ! -path "*/opera/*" \
    ! -path "*/vivaldi/*" \
    -delete 2>/dev/null

# 3. Czyszczenie virt-manager i dconf / Cleaning virt-manager and dconf
echo -e "${GREEN}${MSG_CLEAN_VIRT}${NC}"
USER_ID=$(id -u)
if [ -S "/run/user/$USER_ID/bus" ]; then
    DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$USER_ID/bus" dconf reset /org/virt-manager/virt-manager/urls/isos 2>/dev/null
fi
rm -rf "$HOME/.cache/virt-manager" 2>/dev/null

# 4. Czcionki / Fonts
echo -e "${GREEN}${MSG_REBUILD_FONTS}${NC}"
fc-cache -r

echo -e "\n${BLUE}======================================================${NC}"
echo -e "${BLUE}${MSG_PHASE3_TITLE}${NC}"
echo -e "${BLUE}======================================================${NC}"

# zypper ps sprawdza procesy używające usuniętych plików (po aktualizacji)
# zypper ps checks for processes using deleted files (after the update)
echo -e "${GREEN}${MSG_CHECK_RESTART}${NC}"
if sudo zypper ps 2>/dev/null | grep -iq "reboot is required"; then
    echo -e "\n${RED}******************************************************${NC}"
    echo -e "${RED} ${MSG_RESTART_WARN1} ${NC}"
    echo -e "${YELLOW}${MSG_RESTART_WARN2}${NC}"
    echo -e "${RED}******************************************************${NC}\n"
else
    echo -e "${GREEN}${MSG_NO_RESTART_NEEDED}${NC}"
fi

if [ "$FWUPD_RESTART_NEEDED" = true ]; then
    echo -e "\n${RED}******************************************************${NC}"
    echo -e "${RED} ${MSG_FWUPD_RESTART_NEEDED} ${NC}"
    echo -e "${YELLOW}${MSG_RESTART_WARN2}${NC}"
    echo -e "${RED}******************************************************${NC}\n"
fi

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN}${MSG_DONE_TITLE}${NC}"
echo -e "${GREEN}======================================================${NC}"
echo "$MSG_PRESS_ENTER"
read -r
