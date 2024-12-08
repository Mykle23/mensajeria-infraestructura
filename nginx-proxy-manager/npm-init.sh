#!/bin/bash

# Esperar 30 segundos antes de continuar
echo "Esperando 30 segundos antes de continuar la configuracion automatica..."
sleep 30

# Función para instalar jq si no está disponible
install_jq() {
  echo "Instalando jq..."
  if command -v apt-get &> /dev/null; then
    sudo apt update && sudo apt install -y jq
  elif command -v yum &> /dev/null; then
    sudo yum install -y jq
  elif command -v brew &> /dev/null; then
    brew install jq
  else
    echo "Gestor de paquetes no soportado. Instala jq manualmente y ejecuta nuevamente el script."
  fi
}

# Verificar si jq está instalado
if ! command -v jq &> /dev/null; then
  echo "jq no está instalado."
  install_jq
fi

# Función para verificar el estado de HTTP
wait_for_200() {
  local url=$1
  echo "Esperando a que $url devuelva el estado HTTP 200..."
  until [[ $(curl -s -o /dev/null -w "%{http_code}" "$url") -eq 200 ]]; do
    echo "El estado HTTP aún no es 200. Reintentando en 5 segundos..."
    sleep 5
  done
  echo "El estado HTTP 200 se obtuvo en $url."
}

# Esperar a que Nginx Proxy Manager esté listo
wait_for_200 "http://localhost:81"

# Crear un token de sesión
echo "Intentando obtener el token de sesión..."
TOKEN=$(curl -s -X POST "http://localhost:81/api/tokens" \
  -H "Content-Type: application/json" \
  -d '{"identity":"admin@example.com","secret":"changeme"}' | jq -r '.token')

if [[ -z "$TOKEN" || "$TOKEN" == "null" ]]; then
  echo "Error: No se pudo obtener el token de sesión. Verifica la configuración de Nginx Proxy Manager."
else
  echo "Token de sesión obtenido: $TOKEN"
fi

# Configurar el host proxy para redirigir a API Gateway
echo "Intentando configurar el host proxy..."
RESPONSE=$(curl -s -X POST "http://localhost:81/api/nginx/proxy-hosts" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "domain_names": ["localhost"],
    "forward_scheme": "http",
    "forward_host": "api-gateway",
    "forward_port": 5000,
    "certificate_id": 0,
    "ssl_forced": false,
    "hsts_enabled": false,
    "hsts_subdomains": false,
    "http2_support": false,
    "block_exploits": false,
    "caching_enabled": false,
    "allow_websocket_upgrade": false,
    "access_list_id": 0,
    "advanced_config": "",
    "enabled": true,
    "meta": {
      "letsencrypt_agree": false,
      "dns_challenge": false
    },
    "locations": []
  }')

if echo "$RESPONSE" | grep -q '"id":'; then
  echo "Host proxy configurado con éxito."
else
  echo "Error: No se pudo configurar el host proxy. Respuesta de la API: $RESPONSE"
fi

echo "Host proxy configurado: http://localhost -> http://api-gateway:5000"

# Evitar que el contenedor se apague
exit 0
