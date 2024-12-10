#!/bin/bash

# Configuración
PAGERDUTY_TOKEN="60b1d6aff448459386bbcf5cb31dfee7"
HOSTNAME=$(hostname)
LOG_FILE="/var/log/dns/monitor_bind.log"
INCIDENT_KEY="bind-monitor-incident-$HOSTNAME"

# Asegurar que curl esté disponible
if ! command -v curl &> /dev/null; then
    echo "Error: curl no está instalado. Por favor, instálalo para usar este script." | tee -a "$LOG_FILE"
    exit 1
fi

# Crear archivo de log si no existe
[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"

# Función para registrar eventos en el log
log_event() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Función para enviar un evento a PagerDuty
send_pagerduty_event() {
    local action="$1"
    local summary="$2"
    local severity="$3"
    
    curl_output=$(curl -X POST "https://events.pagerduty.com/v2/enqueue" \
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
        }' 2>&1)
    
    if [ $? -ne 0 ]; then
        log_event "Error al enviar evento a PagerDuty: $curl_output"
    else
        log_event "Evento enviado a PagerDuty: $action - $summary"
    fi
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

    # Intentar reiniciar BIND con reintentos
    attempts=0
    max_attempts=3
    while ! systemctl is-active --quiet named && [ $attempts -lt $max_attempts ]; do
        log_event "Reintentando reiniciar named... intento $((attempts + 1)) de $max_attempts."
        systemctl restart named
        sleep 30
        ((attempts++))
    done

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
        log_event "No se pudo recuperar named después de $max_attempts intentos."
        send_pagerduty_event "trigger" "No se pudo restaurar BIND en $HOSTNAME tras múltiples intentos" "critical"
        exit 1
    fi
else
    log_event "El servicio BIND está funcionando correctamente. No se requiere acción."
fi
