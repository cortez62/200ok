# 200ok
<<<<<<< HEAD
Instala y habilita el servicio.
=======

Dos scripts de proxy/túnel TCP que responden `HTTP/1.1 200 OK` y luego reenvían tráfico hacia un destino local (por defecto `127.0.0.1:22`).

Este repo incluye un instalador para **Ubuntu/Debian** que configura un **servicio systemd** para que arranque automáticamente.

## Requisitos

- VPS Ubuntu/Debian con `systemd`
- Acceso root (o `sudo`)

## Instalación (recomendado)

1) Clona el repo en el VPS:

```bash
apt-get update
apt-get install -y git
git clone <TU_URL_DE_GITHUB> 200ok
cd 200ok
```

2) Instala y habilita el servicio.

### Instalación interactiva (menú)

En el VPS:

```bash
cd 200ok
sudo bash menu.sh
```

- Modo **asyncio** (usa `pythonCortez.py`) — **por defecto**:

```bash
sudo bash install.sh
```

- Modo **threaded** (usa `http_200_stream_dropbear.py`):

```bash
sudo bash install.sh threaded
```

### Cambiar puertos (y host destino)

Formato:

```bash
sudo bash install.sh <asyncio|threaded> [LISTEN_PORT] [TARGET_PORT]
sudo bash install.sh <asyncio|threaded> [LISTEN_PORT] [TARGET_HOST] [TARGET_PORT]
```

Ejemplos:

- Escuchar en 8080 y mandar a SSH 22:

```bash
sudo bash install.sh asyncio 8080 22
```

- Escuchar en 80 y mandar a otro destino/puerto:

```bash
sudo bash install.sh threaded 80 127.0.0.1 2222
```

## Control del servicio

- Ver estado:

```bash
systemctl status 200ok --no-pager
```

- Ver logs en vivo:

```bash
journalctl -u 200ok -f
```

- Reiniciar:

```bash
systemctl restart 200ok
```

- Deshabilitar en boot:

```bash
systemctl disable --now 200ok
```

## Desinstalar

```bash
sudo bash uninstall.sh
```

## Notas importantes

- **Solo puede correr un modo a la vez**, porque ambos scripts escuchan en el **puerto 80**.
- El servicio corre como usuario no-root (`proxy200ok`) y usa capability `CAP_NET_BIND_SERVICE` para poder bindear el puerto 80.
- Cambios de puertos/hosts se hacen editando el script que estés usando y reiniciando el servicio.
>>>>>>> eae2492 (Initial commit)
