#!/bin/bash

# Unofficial Bash Strict Mode
set -euo pipefail
IFS=$'\n\t'

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file for debugging
LOG_FILE="$HOME/termux_setup.log"
exec 2>>"$LOG_FILE"
LAST_STEP="Starting installer"

# Temporary directory for setup
TEMP_DIR=$(mktemp -d)

# Function to print colored status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" = "ok" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" = "warn" ]; then
        echo -e "${YELLOW}!${NC} $message"
    else
        echo -e "${RED}✗${NC} $message"
    fi
}

log_step() {
    LAST_STEP="$1"
    echo -e "\n${BLUE}[*]${NC} $LAST_STEP"
}

fail() {
    local message=$1
    echo -e "${RED}ERROR: $message${NC}"
    echo "ERROR: $message" >> "$LOG_FILE"
    exit 1
}

run_step() {
    local message=$1
    shift
    log_step "$message"
    "$@" || fail "$message failed."
}

append_once() {
    local file=$1
    local line=$2
    mkdir -p "$(dirname "$file")"
    touch "$file"
    grep -Fxq "$line" "$file" || echo "$line" >> "$file"
}

validate_commands() {
    local missing=()
    local cmd

    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ "${#missing[@]}" -gt 0 ]; then
        fail "Missing required command(s): ${missing[*]}. Install them with: pkg install ${missing[*]}"
    fi
}

proot_rootfs_path() {
    local rootfs_path

    for rootfs_path in \
        "$PREFIX/var/lib/proot-distro/installed-rootfs/$distro_alias" \
        "$PREFIX/var/lib/proot-distro/containers/$distro_alias/rootfs"; do
        if [ -d "$rootfs_path" ]; then
            echo "$rootfs_path"
            return 0
        fi
    done

    echo "$PREFIX/var/lib/proot-distro/installed-rootfs/$distro_alias"
}

proot_login() {
    pd login "$distro_alias" --shared-tmp -- env DISPLAY=:0 "$@"
}

configure_sudoers() {
    log_step "Configuring sudo in $distro_alias rootfs"

    proot_login bash -c 'command -v sudo >/dev/null 2>&1 || (apt update && apt install -y sudo)' \
        || fail "Failed to configure sudoers. sudo package could not be installed."

    proot_login bash -c '
set -e
if [ ! -f /etc/sudoers ]; then
    cat > /etc/sudoers <<EOF
root ALL=(ALL:ALL) ALL
%sudo ALL=(ALL:ALL) ALL
EOF
fi
chmod 440 /etc/sudoers
' || fail "Failed to configure sudoers. /etc/sudoers could not be created or repaired."

    proot_login bash -c "grep -Fxq '$username ALL=(ALL) NOPASSWD:ALL' /etc/sudoers || (chmod u+w /etc/sudoers && echo '$username ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers)" \
        || fail "Failed to configure sudoers. Could not add user '$username'."

    proot_login chmod 440 /etc/sudoers \
        || fail "Failed to configure sudoers. Could not set /etc/sudoers permissions."
}

# Function to clean up on exit
finish() {
    local ret=$?
    if [ $ret -ne 0 ] && [ $ret -ne 130 ]; then
        echo -e "${RED}ERROR: An issue occurred during: $LAST_STEP${NC}"
        echo -e "${RED}Please check $LOG_FILE for details.${NC}"
    fi
    rm -rf "$TEMP_DIR"
}

trap finish EXIT

# Function to detect system compatibility
detect_termux() {
    local errors=0
    
    echo -e "\n${BLUE}╔════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║      System Compatibility Check    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════╝${NC}\n"
    
    # Check if running on Android
    if [[ "$(uname -o)" = "Android" ]]; then
        print_status "ok" "Running on Android $(getprop ro.build.version.release)"
    else
        print_status "error" "Not running on Android"
        ((errors+=1))
    fi

    # Check architecture
    local arch=$(uname -m)
    if [[ "$arch" = "aarch64" ]]; then
        print_status "ok" "Architecture: $arch"
    else
        print_status "error" "Unsupported architecture: $arch (requires aarch64)"
        ((errors+=1))
    fi

    # Check for required directories
    if [[ -d "$PREFIX" ]]; then
        print_status "ok" "Termux PREFIX directory found"
    else
        print_status "error" "Termux PREFIX directory not found"
        ((errors+=1))
    fi

    # Check available storage space
    local free_space=$(df -h "$HOME" | awk 'NR==2 {print $4}')
    if [[ $(df "$HOME" | awk 'NR==2 {print $4}') -gt 4194304 ]]; then
        print_status "ok" "Available storage: $free_space"
    else
        print_status "warn" "Low storage space: $free_space (4GB recommended)"
    fi

    # Check RAM
    local total_ram=$(free -m | awk 'NR==2 {print $2}')
    if [[ $total_ram -gt 2048 ]]; then
        print_status "ok" "RAM: ${total_ram}MB"
    else
        print_status "warn" "Low RAM: ${total_ram}MB (2GB recommended)"
    fi

    echo
    if [[ $errors -eq 0 ]]; then
        echo -e "${YELLOW}All system requirements met!${NC}"
        return 0
    else
        echo -e "${RED}Found $errors error(s). System requirements not met.${NC}"
        return 1
    fi
}

# Main installation function
main() {
    clear
    echo -e "\n${BLUE}╔════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║    XFCE Desktop Installation       ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════╝${NC}"

    # Check system compatibility
    if ! detect_termux; then
        echo -e "${YELLOW}Please ensure your system meets the following requirements:${NC}"
        echo "• Termux GitHub release"
        echo "• ARM64 (aarch64) device"
        echo "• Android operating system"
        echo "• At least 4GB free storage"
        echo "• At least 2GB RAM recommended"
        exit 1
    fi

    echo -e "\n${GREEN}This will install XFCE native desktop in Termux"
    echo -e "${GREEN}A Debian or Ubuntu proot-distro is also installed for additional software"
    echo -e "${GREEN}while also enabling hardware acceleration"
    echo -e "${GREEN}This setup has been tested on a Samsung Galaxy S24 Ultra"
    echo -e "${GREEN}It should run on most phones however.${NC}"
    echo -e "\n${RED}Please install the Termux:X11 Android app: ${YELLOW}https://github.com/termux/termux-x11/releases"
    echo -e "\n${YELLOW}Press Enter to continue or Ctrl+C to cancel${NC}"
    
    read -r

    # Continue with your existing installation code here
    echo -n "Please enter username for proot installation: " > /dev/tty
    read username < /dev/tty
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        fail "Invalid username '$username'. Use lowercase letters, numbers, underscores, or hyphens, starting with a letter or underscore."
    fi

    echo -e "\n${YELLOW}Select proot distro:${NC}"
    echo "1) Debian latest"
    echo "2) Ubuntu 24.04"
    echo -n "Choice [1]: " > /dev/tty
    read distro_choice < /dev/tty

    case "${distro_choice:-1}" in
        1)
            distro_image="debian:latest"
            distro_alias="debian"
            distro_label="Debian"
            ;;
        2)
            distro_image="ubuntu:24.04"
            distro_alias="ubuntu"
            distro_label="Ubuntu 24.04"
            ;;
        *)
            fail "Invalid distro selection '$distro_choice'. Choose 1 for Debian latest or 2 for Ubuntu 24.04."
            ;;
    esac

    # Change repository
if ! termux-change-repo; then
    echo "Failed to change repository. Exiting."
    exit 1
fi

# Check if storage access is already granted
if [ -d ~/storage ]; then
    echo "Storage access is already granted"
else
    # Setup Termux Storage Access only if not already granted
    if ! termux-setup-storage; then
        echo "Failed to set up Termux storage. Exiting."
        echo "${YELLOW}Please clear termux data in app info setting and run setup again${NC}"
        exit 1
    fi
fi

# Upgrade packages
if ! pkg upgrade -y -o Dpkg::Options::="--force-confold"; then
    echo "Failed to upgrade packages. Exiting."
    exit 1
fi

# Update termux.properties
if [ -f "$HOME/.termux/termux.properties" ]; then
    sed -i '12s/^#//' $HOME/.termux/termux.properties
else
    echo "Warning: termux.properties file not found. Skipping update."
fi

# Install core dependencies
dependencies=('wget' 'curl' 'tar' 'unzip' 'proot-distro' 'x11-repo' 'tur-repo' 'pulseaudio' 'git')
missing_deps=()
for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        missing_deps+=("$dep")
    fi
done

if [ "${#missing_deps[@]}" -gt 0 ]; then
    if ! pkg install -y "${missing_deps[@]}" -o Dpkg::Options::="--force-confold"; then
        echo "Failed to install missing dependencies: ${missing_deps[*]}. Exiting."
        exit 1
    fi
fi

validate_commands proot-distro pd pulseaudio wget curl tar unzip git

# Create default directories
mkdir -p "$HOME/Desktop" "$HOME/Downloads" "$HOME/.fonts" "$HOME/.config" "$HOME/.config/xfce4/xfconf/xfce-perchannel-xml/" "$HOME/.config/autostart/" "$HOME/.config/gtk-3.0/" "$HOME/.config/xfce4/terminal/" "$HOME/.config/xfce4/panel/" "$HOME/.config/xfce4/panel/launcher-7" "$HOME/.config/xfce4/panel/launcher-10" "$HOME/.config/xfce4/panel/launcher-11"
#ln -s /storage/emulated/0/Music $HOME/Music
#ln -s /storage/emulated/0/Pictures $HOME/Pictures

# Install XFCE desktop environment
xfce_packages=('xfce4' 'xfce4-goodies' 'xfce4-pulseaudio-plugin' 'firefox' 'starship' 'termux-x11-nightly' 'virglrenderer-android' 'mesa-vulkan-icd-freedreno-dri3' 'fastfetch' 'papirus-icon-theme' 'eza' 'bat')
if ! pkg install -y "${xfce_packages[@]}" -o Dpkg::Options::="--force-confold"; then
    echo "Failed to install XFCE packages. Exiting."
    exit 1
fi

validate_commands termux-x11 pulseaudio
if command -v pm >/dev/null 2>&1 && ! pm path com.termux.x11 >/dev/null 2>&1; then
    fail "Termux:X11 Android app is not installed. Install it from https://github.com/termux/termux-x11/releases and rerun this installer."
fi

# Set aliases
append_once "$PREFIX/etc/bash.bashrc" "alias $distro_alias='proot-distro login $distro_alias --user $username --shared-tmp'"
append_once "$PREFIX/etc/bash.bashrc" "alias ls='eza -lF --icons'"
append_once "$PREFIX/etc/bash.bashrc" "alias cat='bat '"
append_once "$PREFIX/etc/bash.bashrc" 'eval "$(starship init bash)"'

# Download starship theme
curl -o $HOME/.config/starship.toml https://raw.githubusercontent.com/phoenixbyrd/Termux_XFCE/refs/heads/main/starship.toml
sed -i "s/phoenixbyrd/$username/" $HOME/.config/starship.toml

# Download Wallpaper
wget -O dark_waves.png https://raw.githubusercontent.com/phoenixbyrd/Termux_XFCE/main/dark_waves.png
mkdir -p "$PREFIX/share/backgrounds/xfce"
mv -f dark_waves.png "$PREFIX/share/backgrounds/xfce/"

# Install WhiteSur-Dark Theme
rm -rf WhiteSur-gtk-theme-2023-04-26 WhiteSur-Dark 2023-04-26.zip
wget -O 2023-04-26.zip https://github.com/vinceliuice/WhiteSur-gtk-theme/archive/refs/tags/2023-04-26.zip
unzip -o 2023-04-26.zip
tar -xf WhiteSur-gtk-theme-2023-04-26/release/WhiteSur-Dark-44-0.tar.xz
mkdir -p "$PREFIX/share/themes"
rm -rf "$PREFIX/share/themes/WhiteSur-Dark"
mv WhiteSur-Dark/ "$PREFIX/share/themes/"
rm -rf WhiteSur*
rm -f 2023-04-26.zip

# Install Fluent Cursor Icon Theme
rm -rf Fluent-icon-theme-2023-02-01 2023-02-01.zip
wget -O 2023-02-01.zip https://github.com/vinceliuice/Fluent-icon-theme/archive/refs/tags/2023-02-01.zip
unzip -o 2023-02-01.zip
mkdir -p "$PREFIX/share/icons"
rm -rf "$PREFIX/share/icons/dist" "$PREFIX/share/icons/dist-dark"
mv Fluent-icon-theme-2023-02-01/cursors/dist "$PREFIX/share/icons/"
mv Fluent-icon-theme-2023-02-01/cursors/dist-dark "$PREFIX/share/icons/"
rm -rf "$HOME"/Fluent*
rm -f 2023-02-01.zip

# Create xsettings.xml for Termux
cat <<'EOF' > $HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml
<?xml version="1.1" encoding="UTF-8"?>

<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="WhiteSur-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
    <property name="DoubleClickTime" type="empty"/>
    <property name="DoubleClickDistance" type="empty"/>
    <property name="DndDragThreshold" type="empty"/>
    <property name="CursorBlink" type="empty"/>
    <property name="CursorBlinkTime" type="empty"/>
    <property name="SoundThemeName" type="empty"/>
    <property name="EnableEventSounds" type="empty"/>
    <property name="EnableInputFeedbackSounds" type="empty"/>
  </property>
  <property name="Xft" type="empty">
    <property name="DPI" type="empty"/>
    <property name="Antialias" type="empty"/>
    <property name="Hinting" type="empty"/>
    <property name="HintStyle" type="empty"/>
    <property name="RGBA" type="empty"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="CanChangeAccels" type="empty"/>
    <property name="ColorPalette" type="empty"/>
    <property name="FontName" type="empty"/>
    <property name="MonospaceFontName" type="empty"/>
    <property name="IconSizes" type="empty"/>
    <property name="KeyThemeName" type="empty"/>
    <property name="MenuImages" type="empty"/>
    <property name="ButtonImages" type="empty"/>
    <property name="MenuBarAccel" type="empty"/>
    <property name="CursorThemeName" type="string" value="dist-dark"/>
    <property name="CursorThemeSize" type="int" value="28"/>
    <property name="DecorationLayout" type="string" value="icon,menu:minimize,maximize,close"/>
    <property name="DialogsUseHeader" type="empty"/>
    <property name="TitlebarMiddleClick" type="empty"/>
    <property name="ThemeName" type="string" value="WhiteSur-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
  </property>
  <property name="Gdk" type="empty">
    <property name="WindowScalingFactor" type="empty"/>
  </property>
  <property name="Xfce" type="empty">
    <property name="SyncThemes" type="bool" value="true"/>
  </property>
</channel>
EOF

cat <<'EOF' > $HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
<?xml version="1.1" encoding="UTF-8"?>

<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="WhiteSur-Dark"/>
    <property name="title_alignment" type="string" value="center"/>
    <property name="button_layout" type="string" value="O|HMC"/>
    <property name="workspace_count" type="int" value="1"/>
    <property name="activate_action" type="string" value="bring"/>
    <property name="borderless_maximize" type="bool" value="true"/>
    <property name="box_move" type="bool" value="false"/>
    <property name="box_resize" type="bool" value="false"/>
    <property name="button_offset" type="int" value="0"/>
    <property name="button_spacing" type="int" value="0"/>
    <property name="click_to_focus" type="bool" value="true"/>
    <property name="cycle_apps_only" type="bool" value="false"/>
    <property name="cycle_draw_frame" type="bool" value="true"/>
    <property name="cycle_raise" type="bool" value="false"/>
    <property name="cycle_hidden" type="bool" value="true"/>
    <property name="cycle_minimum" type="bool" value="true"/>
    <property name="cycle_minimized" type="bool" value="false"/>
    <property name="cycle_preview" type="bool" value="true"/>
    <property name="cycle_tabwin_mode" type="int" value="0"/>
    <property name="cycle_workspaces" type="bool" value="false"/>
    <property name="double_click_action" type="string" value="maximize"/>
    <property name="double_click_distance" type="int" value="5"/>
    <property name="double_click_time" type="int" value="250"/>
    <property name="easy_click" type="string" value="Alt"/>
    <property name="focus_delay" type="int" value="250"/>
    <property name="focus_hint" type="bool" value="true"/>
    <property name="focus_new" type="bool" value="true"/>
    <property name="frame_opacity" type="int" value="100"/>
    <property name="frame_border_top" type="int" value="0"/>
    <property name="full_width_title" type="bool" value="true"/>
    <property name="horiz_scroll_opacity" type="bool" value="false"/>
    <property name="inactive_opacity" type="int" value="100"/>
    <property name="maximized_offset" type="int" value="0"/>
    <property name="mousewheel_rollup" type="bool" value="true"/>
    <property name="move_opacity" type="int" value="100"/>
    <property name="placement_mode" type="string" value="center"/>
    <property name="placement_ratio" type="int" value="20"/>
    <property name="popup_opacity" type="int" value="100"/>
    <property name="prevent_focus_stealing" type="bool" value="false"/>
    <property name="raise_delay" type="int" value="250"/>
    <property name="raise_on_click" type="bool" value="true"/>
    <property name="raise_on_focus" type="bool" value="false"/>
    <property name="raise_with_any_button" type="bool" value="true"/>
    <property name="repeat_urgent_blink" type="bool" value="false"/>
    <property name="resize_opacity" type="int" value="100"/>
    <property name="scroll_workspaces" type="bool" value="true"/>
    <property name="shadow_delta_height" type="int" value="0"/>
    <property name="shadow_delta_width" type="int" value="0"/>
    <property name="shadow_delta_x" type="int" value="0"/>
    <property name="shadow_delta_y" type="int" value="-3"/>
    <property name="shadow_opacity" type="int" value="50"/>
    <property name="show_app_icon" type="bool" value="false"/>
    <property name="show_dock_shadow" type="bool" value="false"/>
    <property name="show_frame_shadow" type="bool" value="true"/>
    <property name="show_popup_shadow" type="bool" value="false"/>
    <property name="snap_resist" type="bool" value="false"/>
    <property name="snap_to_border" type="bool" value="true"/>
    <property name="snap_to_windows" type="bool" value="false"/>
    <property name="snap_width" type="int" value="10"/>
    <property name="vblank_mode" type="string" value="auto"/>
    <property name="tile_on_move" type="bool" value="true"/>
    <property name="title_font" type="string" value="Sans Bold 9"/>
    <property name="title_horizontal_offset" type="int" value="0"/>
    <property name="titleless_maximize" type="bool" value="false"/>
    <property name="title_shadow_active" type="string" value="false"/>
    <property name="title_shadow_inactive" type="string" value="false"/>
    <property name="title_vertical_offset_active" type="int" value="0"/>
    <property name="title_vertical_offset_inactive" type="int" value="0"/>
    <property name="toggle_workspaces" type="bool" value="false"/>
    <property name="unredirect_overlays" type="bool" value="true"/>
    <property name="urgent_blink" type="bool" value="false"/>
    <property name="use_compositing" type="bool" value="true"/>
    <property name="wrap_cycle" type="bool" value="true"/>
    <property name="wrap_layout" type="bool" value="true"/>
    <property name="wrap_resistance" type="int" value="10"/>
    <property name="wrap_windows" type="bool" value="false"/>
    <property name="wrap_workspaces" type="bool" value="false"/>
    <property name="zoom_desktop" type="bool" value="true"/>
    <property name="zoom_pointer" type="bool" value="true"/>
    <property name="workspace_names" type="array">
      <value type="string" value="Workspace 1"/>
    </property>
  </property>
</channel>
EOF

# Create xfce4-desktop.xml with wallpaper setting
cat <<'EOF' > $HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
<?xml version="1.1" encoding="UTF-8"?>

<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitorDexDisplay" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/data/data/com.termux/files/usr/share/backgrounds/xfce/dark_waves.png"/>
        </property>
      </property>
    </property>
  </property>
  <property name="last-settings-migration-version" type="uint" value="1"/>
  <property name="desktop-icons" type="empty">
    <property name="file-icons" type="empty">
      <property name="show-filesystem" type="bool" value="false"/>
      <property name="show-home" type="bool" value="false"/>
      <property name="show-trash" type="bool" value="false"/>
      <property name="show-removable" type="bool" value="false"/>
    </property>
  </property>
  <property name="last" type="empty">
    <property name="window-width" type="int" value="676"/>
    <property name="window-height" type="int" value="502"/>
  </property>
</channel>
EOF

# Create xfce4-panel.xml
cat <<'EOF' > $HOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml
<?xml version="1.1" encoding="UTF-8"?>

<channel name="xfce4-panel" version="1.0">
  <property name="configver" type="int" value="2"/>
  <property name="panels" type="array">
    <value type="int" value="1"/>
    <value type="int" value="2"/>
    <property name="dark-mode" type="bool" value="true"/>
    <property name="panel-1" type="empty">
      <property name="position" type="string" value="p=6;x=0;y=0"/>
      <property name="length" type="uint" value="100"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="icon-size" type="uint" value="0"/>
      <property name="size" type="uint" value="34"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="1"/>
        <value type="int" value="3"/>
        <value type="int" value="10"/>
        <value type="int" value="11"/>
        <value type="int" value="9"/>
        <value type="int" value="8"/>
        <value type="int" value="5"/>
        <value type="int" value="6"/>
        <value type="int" value="2"/>
        <value type="int" value="7"/>
      </property>
      <property name="background-style" type="uint" value="1"/>
      <property name="background-rgba" type="array">
        <value type="double" value="0"/>
        <value type="double" value="0"/>
        <value type="double" value="0"/>
        <value type="double" value="0"/>
      </property>
    </property>
    <property name="panel-2" type="empty">
      <property name="autohide-behavior" type="uint" value="1"/>
      <property name="position" type="string" value="p=10;x=0;y=0"/>
      <property name="length" type="uint" value="1"/>
      <property name="position-locked" type="bool" value="true"/>
      <property name="size" type="uint" value="64"/>
      <property name="plugin-ids" type="array">
        <value type="int" value="12"/>
        <value type="int" value="4"/>
        <value type="int" value="17"/>
      </property>
      <property name="background-style" type="uint" value="1"/>
      <property name="background-rgba" type="array">
        <value type="double" value="0.14117647058823529"/>
        <value type="double" value="0.14117647058823529"/>
        <value type="double" value="0.14117647058823529"/>
        <value type="double" value="1"/>
      </property>
    </property>
  </property>
  <property name="plugins" type="empty">
    <property name="plugin-1" type="string" value="applicationsmenu">
      <property name="button-title" type="string" value="Menu "/>
      <property name="button-icon" type="string" value="start-here"/>
      <property name="show-button-title" type="bool" value="true"/>
    </property>
    <property name="plugin-3" type="string" value="separator">
      <property name="expand" type="bool" value="false"/>
      <property name="style" type="uint" value="2"/>
    </property>
    <property name="plugin-5" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
      <property name="expand" type="bool" value="true"/>
    </property>
    <property name="plugin-6" type="string" value="systray">
      <property name="square-icons" type="bool" value="true"/>
      <property name="known-legacy-items" type="array">
        <value type="string" value="vesktop"/>
        <value type="string" value="onboard"/>
      </property>
    </property>
    <property name="plugin-8" type="string" value="clock">
      <property name="digital-layout" type="uint" value="3"/>
      <property name="digital-time-format" type="string" value="%b %d  %I:%M %p"/>
      <property name="digital-time-font" type="string" value="Sans Bold 12"/>
    </property>
    <property name="plugin-9" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
      <property name="expand" type="bool" value="true"/>
    </property>
    <property name="plugin-12" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-17" type="string" value="separator">
      <property name="style" type="uint" value="0"/>
    </property>
    <property name="plugin-4" type="string" value="tasklist">
      <property name="show-handle" type="bool" value="false"/>
      <property name="show-labels" type="bool" value="false"/>
      <property name="sort-order" type="uint" value="0"/>
    </property>
    <property name="plugin-2" type="string" value="pulseaudio">
      <property name="enable-keyboard-shortcuts" type="bool" value="true"/>
      <property name="known-players" type="string" value="firefox-default"/>
    </property>
    <property name="plugin-7" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="17367087851.desktop"/>
      </property>
    </property>
    <property name="plugin-10" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="17367088062.desktop"/>
      </property>
    </property>
    <property name="plugin-11" type="string" value="launcher">
      <property name="items" type="array">
        <value type="string" value="17367088133.desktop"/>
      </property>
    </property>
  </property>
</channel>
EOF

# Create gtk.css with panel styling
cat <<'EOF' > $HOME/.config/gtk-3.0/gtk.css
.xfce4-panel {
   border-top-left-radius: 10px;
   border-top-right-radius: 10px;
}
EOF

# Create bookmarks with custom name
cat <<EOF > $HOME/.config/gtk-3.0/bookmarks
file:////data/data/com.termux/files/home/Downloads
file:///data/data/com.termux/files/usr/var/lib/proot-distro/installed-rootfs/$distro_alias/home/$username $distro_label Home
file:////data/data/com.termux/files/home/storage/shared/ Android Storage
EOF

# Setup xfce4-terminal theme
cat <<'EOF' > $HOME/.config/xfce4/terminal/terminalrc
[Configuration]
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBellUrgent=FALSE
MiscBordersDefault=TRUE
MiscCursorBlinks=FALSE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscDefaultGeometry=80x24
MiscInheritGeometry=FALSE
MiscMenubarDefault=TRUE
MiscMouseAutohide=FALSE
MiscMouseWheelZoom=TRUE
MiscToolbarDefault=FALSE
MiscConfirmClose=TRUE
MiscCycleTabs=TRUE
MiscTabCloseButtons=TRUE
MiscTabCloseMiddleClick=TRUE
MiscTabPosition=GTK_POS_TOP
MiscHighlightUrls=TRUE
MiscMiddleClickOpensUri=FALSE
MiscCopyOnSelect=FALSE
MiscShowRelaunchDialog=TRUE
MiscRewrapOnResize=TRUE
MiscUseShiftArrowsToScroll=FALSE
MiscSlimTabs=FALSE
MiscNewTabAdjacent=FALSE
MiscSearchDialogOpacity=100
MiscShowUnsafePasteDialog=TRUE
MiscRightClickAction=TERMINAL_RIGHT_CLICK_ACTION_CONTEXT_MENU
BackgroundMode=TERMINAL_BACKGROUND_TRANSPARENT
BackgroundDarkness=0.900000
ColorPalette=#000000;#cc0000;#4e9a06;#c4a000;#3465a4;#75507b;#06989a;#d3d7cf;#555753;#ef2929;#8ae234;#fce94f;#739fcf;#ad7fa8;#34e2e2;#eeeeec
ColorBackground=#291f291f340d
TitleMode=TERMINAL_TITLE_HIDE
ScrollingUnlimited=TRUE
ScrollingBar=TERMINAL_SCROLLBAR_NONE
FontName=Cascadia Mono PL 12
EOF

# launcher-7
cat <<EOF > $HOME/.config/xfce4/panel/launcher-7/17367087851.desktop
[Desktop Entry]
Version=1.0
Type=Application
Name=Kill Termux X11
Comment=
Exec=kill_termux_x11
Icon=system-shutdown
Categories=System;
Path=
StartupNotify=false
X-XFCE-Source=file:///data/data/com.termux/files/home/Desktop/kill_termux_x11.desktop
EOF

# launcher-10
cat <<EOF > $HOME/.config/xfce4/panel/launcher-10/17367088062.desktop
[Desktop Entry]
Version=1.0
Type=Application
Exec=exo-open --launch FileManager %u
Icon=user-blue-home
StartupNotify=true
Terminal=false
Categories=Utility;X-XFCE;X-Xfce-Toplevel;
Keywords=file;manager;explorer;browse;filesystem;directory;folder;xfce;
OnlyShowIn=XFCE;
X-XFCE-MimeType=inode/directory;x-scheme-handler/trash;
X-AppStream-Ignore=True
Name=File Manager
Comment=Browse the file system
X-XFCE-Source=file:///data/data/com.termux/files/home/Desktop/xfce4-file-manager.desktop
EOF

#launcher-11
cat <<EOF > $HOME/.config/xfce4/panel/launcher-11/17367088133.desktop
[Desktop Entry]
Version=1.0
Type=Application
Exec=exo-open --launch TerminalEmulator
Icon=org.xfce.terminalemulator
StartupNotify=true
Terminal=false
Categories=Utility;X-XFCE;X-Xfce-Toplevel;
Keywords=terminal;command line;shell;console;xfce;
OnlyShowIn=XFCE;
X-AppStream-Ignore=True
Name=Terminal Emulator
Comment=Use the command line
X-XFCE-Source=file:///data/data/com.termux/files/home/Desktop/xfce4-terminal-emulator.desktop
EOF

# Setup Fonts
wget -O CascadiaCode-2111.01.zip https://github.com/microsoft/cascadia-code/releases/download/v2111.01/CascadiaCode-2111.01.zip
unzip -o CascadiaCode-2111.01.zip
mv otf/static/* .fonts/ && rm -rf otf
mv ttf/* .fonts/ && rm -rf ttf/
rm -rf woff2/ && rm -rf CascadiaCode-2111.01.zip

wget -O Meslo.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/Meslo.zip
unzip -o Meslo.zip
mv *.ttf .fonts/
rm -f Meslo.zip
rm -f LICENSE.txt
rm -f readme.md

wget -O NotoColorEmoji-Regular.ttf https://github.com/phoenixbyrd/Termux_XFCE/raw/main/NotoColorEmoji-Regular.ttf
mv NotoColorEmoji-Regular.ttf .fonts

wget -O font.ttf https://github.com/phoenixbyrd/Termux_XFCE/raw/main/font.ttf
mkdir -p "$HOME/.termux"
mv font.ttf .termux/font.ttf

# Create start script
cat <<'EOF' > $PREFIX/bin/start
#!/bin/bash

# Kill open X11 processes
kill -9 $(pgrep -f "termux.x11") 2>/dev/null

# Get the phone manufacturer
MANUFACTURER=$(getprop ro.product.manufacturer | tr '[:upper:]' '[:lower:]')

# Check the manufacturer
if [[ "$MANUFACTURER" == "samsung" ]]; then
    [ -d ~/.config/pulse ] && rm -rf ~/.config/pulse
    LD_PRELOAD=/system/lib64/libskcodec.so pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1
else
   pulseaudio --start --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" --exit-idle-time=-1
fi

# Set audio server
export PULSE_SERVER=127.0.0.1

# Prepare termux-x11 session
if ! command -v termux-x11 >/dev/null 2>&1; then
    echo "termux-x11 command not found. Install termux-x11-nightly in Termux and the Termux:X11 Android app."
    exit 1
fi

if [ -z "${TMPDIR:-}" ] || [ ! -d "$TMPDIR" ]; then
    echo "TMPDIR is not set correctly. Termux:X11 requires the shared Termux tmp directory."
    exit 1
fi

export XDG_RUNTIME_DIR=${TMPDIR}
termux-x11 :0 >/dev/null &

# Wait a bit until termux-x11 gets started.
sleep 3

# Launch Termux X11 main activity
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity > /dev/null 2>&1
sleep 1

# Function to check the GPU type
gpu_check() {
    # Attempt to detect GPU using getprop
    gpu_egl=$(getprop ro.hardware.egl)
    gpu_vulkan=$(getprop ro.hardware.vulkan)

    # Combine unique GPU information
    detected_gpu="$(echo -e "$gpu_egl\n$gpu_vulkan" | sort -u | tr '\n' ' ' | sed 's/ $//')"

    if echo "$detected_gpu" | grep -iq "adreno"; then
        echo "GPU detected: $detected_gpu"
        MESA_NO_ERROR=1 MESA_GL_VERSION_OVERRIDE=4.3COMPAT MESA_GLES_VERSION_OVERRIDE=3.2 LIBGL_DRI3_DISABLE=1 virgl_test_server_android & > /dev/null 2>&1
    elif echo "$detected_gpu" | grep -iq "mali"; then
        echo "GPU detected: $detected_gpu"
        MESA_NO_ERROR=1 MESA_GL_VERSION_OVERRIDE=4.3COMPAT MESA_GLES_VERSION_OVERRIDE=3.2 LIBGL_DRI3_DISABLE=1 virgl_test_server_android --angle-gl & > /dev/null 2>&1
    else
        echo "Unknown GPU type detected: $detected_gpu"
        exit 1
    fi
}

# Run the GPU check function
gpu_check

# Run XFCE4 Desktop
dbus-daemon --session --address=unix:path=$PREFIX/var/run/dbus-session &
env DISPLAY=:0 GALLIUM_DRIVER=virpipe dbus-launch --exit-with-session xfce4-session & > /dev/null 2>&1

exit 0
EOF

chmod +x $PREFIX/bin/start

# Create shutdown utility
cat <<'EOF' > $PREFIX/bin/kill_termux_x11
#!/bin/bash

# Kill Termux-X11
am broadcast -a com.termux.x11.ACTION_STOP -p com.termux.x11 > /dev/null 2>&1

# Kill Termux
pkill -f termux

EOF

chmod +x $PREFIX/bin/kill_termux_x11

# Create kill_termux_x11.desktop
echo "[Desktop Entry]
Version=1.0
Type=Application
Name=Kill Termux X11
Comment=
Exec=kill_termux_x11
Icon=system-shutdown
Categories=System;
Path=
StartupNotify=false
" > $HOME/Desktop/kill_termux_x11.desktop
chmod +x $HOME/Desktop/kill_termux_x11.desktop
mv $HOME/Desktop/kill_termux_x11.desktop $PREFIX/share/applications

# Create prun script
cat <<EOF > $PREFIX/bin/prun
#!/bin/bash
distro_alias="$distro_alias"
rootfs="\$PREFIX/var/lib/proot-distro/installed-rootfs/\$distro_alias"
varname=\$(basename "\$rootfs"/home/*)
pd login "\$distro_alias" --user "\$varname" --shared-tmp -- env DISPLAY=:0 "\$@"

EOF
chmod +x $PREFIX/bin/prun

# Create zrun script
cat <<EOF > $PREFIX/bin/zrun
#!/bin/bash
distro_alias="$distro_alias"
rootfs="\$PREFIX/var/lib/proot-distro/installed-rootfs/\$distro_alias"
varname=\$(basename "\$rootfs"/home/*)
pd login "\$distro_alias" --user "\$varname" --shared-tmp -- env DISPLAY=:0 MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform "\$@"

EOF
chmod +x $PREFIX/bin/zrun

# Create zrunhud script
cat <<EOF > $PREFIX/bin/zrunhud
#!/bin/bash
distro_alias="$distro_alias"
rootfs="\$PREFIX/var/lib/proot-distro/installed-rootfs/\$distro_alias"
varname=\$(basename "\$rootfs"/home/*)
pd login "\$distro_alias" --user "\$varname" --shared-tmp -- env DISPLAY=:0 MESA_LOADER_DRIVER_OVERRIDE=zink TU_DEBUG=noconform GALLIUM_HUD=fps "\$@"

EOF
chmod +x $PREFIX/bin/zrunhud

# App Installer

if [ -d "$HOME/.config/App-Installer/.git" ]; then
    if ! git -C "$HOME/.config/App-Installer" pull --ff-only; then
        print_status "warn" "Could not update existing App-Installer checkout; continuing with local copy"
    fi
else
    rm -rf "$HOME/.config/App-Installer"
    git clone https://github.com/phoenixbyrd/App-Installer.git "$HOME/.config/App-Installer"
fi
chmod +x $HOME/.config/App-Installer/*

echo "[Desktop Entry]
Version=1.0
Type=Application
Name=App Installer
Comment=
Exec=/data/data/com.termux/files/home/.config/App-Installer/app-installer
Icon=package-install
Categories=System;
Path=
Terminal=false
StartupNotify=false
" > $HOME/Desktop/App-Installer.desktop
chmod +x $HOME/Desktop/App-Installer.desktop
cp $HOME/Desktop/App-Installer.desktop $PREFIX/share/applications

# cp2menu

wget -O "$PREFIX/bin/cp2menu" https://github.com/phoenixbyrd/Termux_XFCE/raw/refs/heads/main/cp2menu
chmod +x $PREFIX/bin/cp2menu

echo "[Desktop Entry]
Version=1.0
Type=Application
Name=cp2menu
Comment=
Exec=cp2menu
Icon=edit-move
Categories=System;
Path=
Terminal=false
StartupNotify=false
" > $PREFIX/share/applications/cp2menu.desktop
chmod +x $PREFIX/share/applications/cp2menu.desktop

# Install proot packages
pkgs_proot=('sudo' 'onboard' 'conky-all' 'flameshot')

# Install selected proot rootfs
proot_rootfs=$(proot_rootfs_path)
if [ -d "$proot_rootfs" ]; then
    print_status "ok" "$distro_label rootfs already installed; reusing it"
else
    run_step "Installing $distro_label rootfs" pd install "$distro_image"
    proot_rootfs=$(proot_rootfs_path)
    [ -d "$proot_rootfs" ] || fail "Installed $distro_label, but could not find its rootfs directory."
fi

run_step "Updating $distro_label package lists" proot_login apt update
run_step "Upgrading $distro_label packages" proot_login apt upgrade -y
run_step "Installing $distro_label desktop helper packages" proot_login apt install "${pkgs_proot[@]}" -y -o Dpkg::Options::="--force-confold"

# Create user and groups idempotently
proot_login bash -c 'for group in users storage wheel audio video; do getent group "$group" >/dev/null || groupadd "$group"; done' \
    || fail "Failed to create required groups in $distro_label."
proot_login bash -c "id -u '$username' >/dev/null 2>&1 || useradd -m -g users -G wheel,audio,video,storage -s /bin/bash '$username'" \
    || fail "Failed to create user '$username' in $distro_label."
proot_login usermod -aG wheel,audio,video,storage "$username" \
    || fail "Failed to update groups for user '$username' in $distro_label."

configure_sudoers

proot_home="$proot_rootfs/home/$username"
mkdir -p "$proot_home"

cat <<EOF > "$HOME/.config/gtk-3.0/bookmarks"
file:////data/data/com.termux/files/home/Downloads
file://$proot_home $distro_label Home
file:////data/data/com.termux/files/home/storage/shared/ Android Storage
EOF

# Set proot DISPLAY and aliases
append_once "$proot_home/.bashrc" "export DISPLAY=:0"
append_once "$proot_home/.bashrc" "alias ls='eza -lF --icons'"
append_once "$proot_home/.bashrc" "alias cat='bat '"
append_once "$proot_home/.bashrc" 'eval "$(starship init bash)"'

# Set proot timezone
timezone=$(getprop persist.sys.timezone)
if [ -n "$timezone" ]; then
    proot_login rm -f /etc/localtime
    proot_login cp "/usr/share/zoneinfo/$timezone" /etc/localtime
else
    print_status "warn" "Android timezone property is empty; leaving proot timezone unchanged"
fi

# Setup Hardware Acceleration in proot
proot_login wget -O /tmp/mesa-vulkan-kgsl_24.1.0-devel-20240120_arm64.deb https://github.com/phoenixbyrd/Termux_XFCE/raw/main/mesa-vulkan-kgsl_24.1.0-devel-20240120_arm64.deb
proot_login apt install -y /tmp/mesa-vulkan-kgsl_24.1.0-devel-20240120_arm64.deb

mkdir -p "$proot_home/.config"

# Download proot starship theme
curl -o "$proot_home/.config/starship.toml" https://raw.githubusercontent.com/phoenixbyrd/Termux_XFCE/refs/heads/main/starship_proot.toml
sed -i "s/phoenixbyrd/$username/" "$proot_home/.config/starship.toml"

# Apply cursor theme
rm -rf "$proot_rootfs/usr/share/icons/dist-dark"
cp -r "$PREFIX/share/icons/dist-dark" "$proot_rootfs/usr/share/icons/dist-dark"
cat <<'EOF' > "$proot_home/.Xresources"
Xcursor.theme: dist-dark
EOF

wget -O conky.tar.gz https://github.com/phoenixbyrd/Termux_XFCE/raw/main/conky.tar.gz
tar -xvzf conky.tar.gz
rm -f conky.tar.gz
rm -rf "$proot_home/.config/conky"
mv "$HOME/.config/conky/" "$proot_home/.config/"

# Conky
cp "$proot_rootfs/usr/share/applications/conky.desktop" "$HOME/.config/autostart/"
sed -i 's|^Exec=.*$|Exec=prun conky -c .config/conky/Alterf/Alterf.conf|' $HOME/.config/autostart/conky.desktop

# Flameshot
cp "$proot_rootfs/usr/share/applications/org.flameshot.Flameshot.desktop" "$HOME/.config/autostart/"
sed -i 's|^Exec=.*$|Exec=prun flameshot|' $HOME/.config/autostart/org.flameshot.Flameshot.desktop

chmod +x $HOME/.config/autostart/*.desktop

}

# Start installation
main

clear
# Display usage instructions
echo -e "\n${BLUE}╔════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         Setup Complete!            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════╝${NC}\n"

echo -e "${GREEN}Available Commands:${NC}"
echo -e "${YELLOW}start${NC}"
echo -e "Launches the XFCE desktop environment with hardware acceleration enabled\n"

echo -e "${YELLOW}$distro_alias${NC}"
echo -e "Enters the $distro_label proot environment for installing additional aarch64 packages\n"

echo -e "${YELLOW}prun${NC}"
echo -e "Executes $distro_label proot applications directly from Termux\n"

echo -e "${YELLOW}zrun${NC}"
echo -e "Runs $distro_label applications with hardware acceleration enabled\n"

echo -e "${YELLOW}zrunhud${NC}"
echo -e "Same as zrun but includes an FPS overlay for performance monitoring\n"

echo -e "${GREEN}Note:${NC} For Firefox hardware acceleration:"
echo -e "1. Open Firefox settings"
echo -e "2. Search for 'performance'"
echo -e "3. Uncheck the hardware acceleration option\n"

echo -e "${YELLOW}Installation complete! Use 'start' to launch your desktop environment.${NC}\n"


source $PREFIX/etc/bash.bashrc
termux-reload-settings
rm -f install_xfce_native.sh
