#!/bin/bash

# Configuración
PAGERDUTY_TOKEN="60b1d6aff448459386bbcf5cb31dfee7"
HOSTNAME=$(hostname)
LOG_FILE="/var/log/dns/monitor_bind.log"
INCIDENT_KEY="bind-monitor-incident-$HOSTNAME"

# Función para registrar eventos en el log
log_event() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Función para enviar un evento a PagerDuty
send_pagerduty_event() {
    local action="$1"
    local summary="$2"
    local severity="$3"
    
    curl -X POST "https://events.pagerduty.com/v2/enqueue" \
        -H "Content-Type: application/json" \
        -d '{
            "routing_key": "'"$PAGERDUTY_TOKEN"'",
            "event_action": "'"$action"'",
            "dedup_key": "'"$INCIDENT_KEY"'",
            "payload": {
                "summary": "'"$summary"'",
                "source": "'"$HOSTNAME"'",
                "severity": "'"$severity"'"
            }
        }' > /dev/null 2>&1
}

# Verificar si el servicio bind está activo
if ! systemctl is-active --quiet named; then
    log_event "El servicio BIND está caído. Iniciando acciones correctivas."

    # Enviar alerta a PagerDuty
    send_pagerduty_event "trigger" "BIND caído en $HOSTNAME" "critical"

    # Detener Keepalived
    if systemctl is-active --quiet keepalived; then
        log_event "Deteniendo keepalived."
        systemctl stop keepalived
        log_event "Esperando 60 segundos antes de intentar reiniciar BIND."
        sleep 60
    else
        log_event "Keepalived ya estaba detenido."
    fi

    # Tratar de reiniciar BIND
    log_event "Intentando reiniciar named (BIND)."
    if systemctl restart named; then
        if systemctl is-active --quiet named; then
            log_event "Servicio named reiniciado y funcionando correctamente."

            # Solo si BIND está funcionando, reiniciar Keepalived
            log_event "Iniciando keepalived ya que BIND está activo."
            if systemctl start keepalived; then
                log_event "Servicio keepalived reiniciado exitosamente."
                log_event "Marcando el incidente en PagerDuty como resuelto."
                send_pagerduty_event "resolve" "Servicios restaurados en $HOSTNAME: BIND y Keepalived funcionando" "info"
            else
                log_event "Error al reiniciar keepalived. Verifica manualmente."
                send_pagerduty_event "trigger" "Error al reiniciar Keepalived en $HOSTNAME" "error"
            fi
        else
            log_event "Servicio named sigue inactivo después del intento de reinicio."
            send_pagerduty_event "trigger" "No se pudo restaurar BIND en $HOSTNAME" "critical"
        fi
    else
        log_event "Error al reiniciar named. Verifica manualmente."
        send_pagerduty_event "trigger" "Error al reiniciar BIND en $HOSTNAME" "critical"
    fi
else
    log_event "El servicio BIND está funcionando correctamente. No se requiere acción."
fi
