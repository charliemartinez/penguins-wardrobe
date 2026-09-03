#!/bin/bash
# ----------------------------------------------------------------------
# Configuración de LightDM para Quirinux
# Ejecutado por tailor durante el finalize del wardrobe.
# ----------------------------------------------------------------------

set -e

# ----------------------------------------------------------------------
# 1. Determinar el usuario objetivo (doas/sudo compatible)
# ----------------------------------------------------------------------
if [ -n "$DOAS_USER" ]; then
    TARGET_USER="$DOAS_USER"
elif [ -n "$SUDO_USER" ]; then
    TARGET_USER="$SUDO_USER"
else
    TARGET_USER="charlie"
fi

echo "[config_lightdm] Usuario objetivo: $TARGET_USER"

# ----------------------------------------------------------------------
# 2. Determinar el archivo de configuración de LightDM
# ----------------------------------------------------------------------
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
if [ -d /etc/lightdm/lightdm.conf.d ]; then
    mkdir -p /etc/lightdm/lightdm.conf.d
    LIGHTDM_CONF="/etc/lightdm/lightdm.conf.d/99-quirinux.conf"
fi

echo "[config_lightdm] Archivo de configuración: $LIGHTDM_CONF"

# ----------------------------------------------------------------------
# 3. Configuración completa de LightDM (sobrescribe cualquier valor previo)
# ----------------------------------------------------------------------
cat > "$LIGHTDM_CONF" <<EOF
[Seat:*]
# Autologin para el usuario principal
autologin-user=${TARGET_USER}
autologin-user-timeout=0

# FORZAR sesión XFCE en todos los casos (login manual y autologin)
# Esto previene que lightdm caiga al fallback "lightdm-xsession" en
# instalaciones frescas donde el usuario no tenía sesión guardada.
user-session=xfce
autologin-session=xfce

# Configuración estándar
allow-user-switching=true
allow-guest=false
greeter-session=lightdm-gtk-greeter
EOF

echo "[config_lightdm] Configuración escrita en $LIGHTDM_CONF"

# ----------------------------------------------------------------------
# 4. Fondo del greeter (solo si existe el directorio de backgrounds)
# ----------------------------------------------------------------------
COSTUME="${1:-quirinux}"
BACKGROUND_DIR="/usr/share/backgrounds/${COSTUME}"
if [ -d "$BACKGROUND_DIR" ]; then
    BACKGROUND=$(ls "$BACKGROUND_DIR"/*.jpg 2>/dev/null | head -1)
    if [ -n "$BACKGROUND" ] && [ -f /etc/lightdm/lightdm-gtk-greeter.conf ]; then
        # Agregar solo si no está ya configurado
        if ! grep -q "^background=" /etc/lightdm/lightdm-gtk-greeter.conf 2>/dev/null; then
            echo "background=${BACKGROUND}" >> /etc/lightdm/lightdm-gtk-greeter.conf
        else
            sed -i "s|^background=.*|background=${BACKGROUND}|" /etc/lightdm/lightdm-gtk-greeter.conf
        fi
        echo "[config_lightdm] Fondo del greeter configurado: $BACKGROUND"
    fi
fi

# ----------------------------------------------------------------------
# 5. Forzar sesión XFCE en .dmrc (skel y usuarios existentes)
# ----------------------------------------------------------------------
# Esto es CRÍTICO: lightdm lee .dmrc y AccountsService para determinar
# la sesión del usuario. En instalaciones frescas, antes de que XFCE
# esté instalado, lightdm guarda "lightdm-xsession" como sesión por
# defecto, lo que causa el error "unable to load a failsafe session".

# 5a. Archivo .dmrc en /etc/skel (para usuarios futuros)
mkdir -p /etc/skel
printf "[Desktop]\nSession=xfce\n" > /etc/skel/.dmrc
chmod 644 /etc/skel/.dmrc
echo "[config_lightdm] /etc/skel/.dmrc configurado con Session=xfce"

# 5b. Archivos .dmrc de usuarios existentes
for h in /home/*; do
    [ -d "$h" ] || continue
    u=$(basename "$h")
    # Solo usuarios reales (UID >= 1000)
    id "$u" >/dev/null 2>&1 || continue
    uid=$(id -u "$u")
    [ "$uid" -ge 1000 ] 2>/dev/null || continue
    
    if [ -f "$h/.dmrc" ]; then
        sed -i "s/^Session=.*/Session=xfce/" "$h/.dmrc"
        # Si no hay línea Session, agregarla
        if ! grep -q "^Session=" "$h/.dmrc"; then
            echo "Session=xfce" >> "$h/.dmrc"
        fi
    else
        printf "[Desktop]\nSession=xfce\n" > "$h/.dmrc"
    fi
    chown "$u:$u" "$h/.dmrc" 2>/dev/null || true
    echo "[config_lightdm] $h/.dmrc configurado para usuario $u"
done

# ----------------------------------------------------------------------
# 6. Corregir AccountsService (lightdm lo lee con prioridad sobre .dmrc)
# ----------------------------------------------------------------------
if [ -d /var/lib/AccountsService/users ]; then
    for f in /var/lib/AccountsService/users/*; do
        [ -f "$f" ] || continue
        # Corregir XSession y Session si existen
        if grep -q "^XSession=" "$f"; then
            sed -i "s/^XSession=.*/XSession=xfce/" "$f"
        else
            echo "XSession=xfce" >> "$f"
        fi
        echo "[config_lightdm] AccountsService $(basename "$f") corregido a xfce"
    done
fi

# ----------------------------------------------------------------------
# 7. Asegurar que lightdm sea el display manager por defecto
# ----------------------------------------------------------------------
if [ -x /usr/sbin/lightdm ]; then
    echo "/usr/sbin/lightdm" > /etc/X11/default-display-manager
    echo "[config_lightdm] LightDM configurado como display manager por defecto"
fi

# ----------------------------------------------------------------------
# 8. Habilitar lightdm según el sistema de init
# ----------------------------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
    # systemd
    systemctl set-default graphical.target 2>/dev/null || true
    systemctl enable lightdm.service 2>/dev/null || true
    # Deshabilitar otros DM
    for dm in slim gdm3 gdm sddm; do
        systemctl disable "${dm}.service" 2>/dev/null || true
        systemctl mask "${dm}.service" 2>/dev/null || true
    done
    echo "[config_lightdm] LightDM habilitado vía systemd"
else
    # sysvinit / Devuan
    if [ -x /usr/sbin/update-rc.d ]; then
        for dm in slim gdm3 gdm sddm; do
            if [ -f "/etc/init.d/${dm}" ]; then
                update-rc.d -f "${dm}" remove >/dev/null 2>&1 || true
            fi
        done
        update-rc.d lightdm defaults >/dev/null 2>&1 || true
        update-rc.d lightdm enable >/dev/null 2>&1 || true
        echo "[config_lightdm] LightDM habilitado vía sysvinit"
    fi
fi

echo "[config_lightdm] Configuración completada exitosamente"
exit 0
