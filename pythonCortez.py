#!/usr/bin/env python3
"""
🚀 Proxy Asyncio — Inyección COMPATIBLE (recv 4096)
✔ Método de inyección IGUAL al script select/hilos
✔ Sin illegal packet size
✔ Sin tocar velocidad
✔ KeepAlive TCP REAL (anti reset en subida)
✔ Ultra estable
"""

import asyncio
import os
import socket
import sys

# ================= CONFIG =================
# Se pueden sobreescribir con variables de entorno:
# LISTEN_HOST, LISTEN_PORT, TARGET_HOST, TARGET_PORT
LISTEN_HOST = os.getenv("LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.getenv("LISTEN_PORT", "80"))
TARGET_HOST = os.getenv("TARGET_HOST", "127.0.0.1")
TARGET_PORT = int(os.getenv("TARGET_PORT", "22"))

BUFFER_SIZE = 65536
MAX_CLIENTS = 70
TIMEOUT = 60

# === RESPONSE EXACTO (NO CAMBIAR) ===
HEAD = (
    "HTTP/1.1 200 OK\r\n"
    "Server: Linear-650KBps\r\n"
    "Connection: keep-alive\r\n\r\n"
)
# ===================================


def apply_keepalive(sock):
    """🔥 KEEPALIVE REAL A NIVEL KERNEL (NO CPU)"""
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)

        # Linux keepalive tuning
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 30)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, 10)
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 3)
    except Exception:
        pass


class AsyncProxy:
    def __init__(self):
        self.clients = 0
        self.lock = asyncio.Lock()

    async def handle_client(self, reader, writer):
        peer = writer.get_extra_info("peername")
        if not peer:
            writer.close()
            return

        async with self.lock:
            if self.clients >= MAX_CLIENTS:
                writer.close()
                return
            self.clients += 1

        print(f"[+] {peer} conectado ({self.clients}/{MAX_CLIENTS})")

        try:
            # ================= INYECCIÓN CORRECTA =================
            try:
                data = await asyncio.wait_for(
                    reader.read(4096),   # EXACTO como client.recv(4096)
                    timeout=5
                )
                if not data:
                    return
            except:
                return

            writer.write(HEAD.encode())
            await writer.drain()
            # ======================================================

            # Conectar al SSH
            target_reader, target_writer = await asyncio.open_connection(
                TARGET_HOST, TARGET_PORT
            )

            # ====== TCP TUNING + KEEPALIVE (CLIENTE) ======
            client_sock = writer.get_extra_info("socket")
            if client_sock:
                client_sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                client_sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 524288)
                client_sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 524288)
                apply_keepalive(client_sock)

            # ====== TCP TUNING + KEEPALIVE (SSH) ======
            ssh_sock = target_writer.get_extra_info("socket")
            if ssh_sock:
                ssh_sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                ssh_sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 524288)
                ssh_sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 524288)
                apply_keepalive(ssh_sock)

            # Forward bidireccional NATIVO (SIN CAMBIOS)
            up = asyncio.create_task(
                self.pipe(reader, target_writer)
            )
            down = asyncio.create_task(
                self.pipe(target_reader, writer)
            )

            done, pending = await asyncio.wait(
                [up, down],
                return_when=asyncio.FIRST_COMPLETED
            )

            for task in pending:
                task.cancel()

        except Exception as e:
            print(f"[ERR {peer}] {e}")

        finally:
            try:
                writer.close()
                target_writer.close()
                await writer.wait_closed()
                await target_writer.wait_closed()
            except:
                pass

            async with self.lock:
                self.clients -= 1

            print(f"[-] {peer} desconectado ({self.clients})")

    async def pipe(self, reader, writer):
        try:
            while True:
                data = await reader.read(BUFFER_SIZE)
                if not data:
                    break
                writer.write(data)
                await writer.drain()
        except:
            pass

    async def run(self):
        server = await asyncio.start_server(
            self.handle_client,
            LISTEN_HOST,
            LISTEN_PORT,
            reuse_address=True,
            backlog=200
        )

        print(f"""
🚀 HTTP 200 Proxy — ASYNCIO (KEEPALIVE REAL)
✔ recv(4096) + 200 OK
✔ Sin illegal packet size
✔ Sin reset en subida
✔ Sin reconexiones idle
✔ Bajo CPU
✔ Clientes: {MAX_CLIENTS}
✔ Buffer: {BUFFER_SIZE // 1024} KB
Puerto: {LISTEN_PORT}
""")

        async with server:
            await server.serve_forever()


async def main():
    proxy = AsyncProxy()
    await proxy.run()


if __name__ == "__main__":
    if sys.version_info < (3, 7):
        print("Python 3.7+ requerido")
        sys.exit(1)

    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nProxy detenido")