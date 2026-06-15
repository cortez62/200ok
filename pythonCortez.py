#!/usr/bin/env python3
import asyncio
import os
import socket
import sys

# ================= CONFIG =================
LISTEN_HOST = os.getenv("LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.getenv("LISTEN_PORT", "80"))

TARGET_HOST = os.getenv("TARGET_HOST", "127.0.0.1")
TARGET_PORT = int(os.getenv("TARGET_PORT", "22"))

BUFFER_SIZE = 65536

# GLOBAL PARA TODOS LOS USUARIOS
MAX_CLIENTS = 80

TIMEOUT = 120
BACKLOG = 100

HEAD = (
    "HTTP/1.1 200 OK\r\n"
    "Server: Linear-650KBps\r\n"
    "Connection: keep-alive\r\n\r\n"
)


def apply_keepalive(sock):
    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)

        try:
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPIDLE, 30)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPINTVL, 10)
            sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_KEEPCNT, 3)
        except Exception:
            pass

    except Exception:
        pass


def tune_socket(sock):
    try:
        sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except Exception:
        pass

    try:
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 524288)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 524288)
    except Exception:
        pass

    apply_keepalive(sock)


class AsyncProxy:
    def __init__(self):
        self.clients = 0
        self.lock = asyncio.Lock()

    async def handle_client(self, reader, writer):
        peer = writer.get_extra_info("peername")
        target_writer = None

        if not peer:
            writer.close()
            await writer.wait_closed()
            return

        async with self.lock:
            if self.clients >= MAX_CLIENTS:
                print(f"[LIMIT] {peer} rechazado ({self.clients}/{MAX_CLIENTS})")
                writer.close()
                await writer.wait_closed()
                return

            self.clients += 1

        print(f"[+] {peer} conectado ({self.clients}/{MAX_CLIENTS})")

        try:
            client_sock = writer.get_extra_info("socket")
            if client_sock:
                tune_socket(client_sock)

            # Leer payload inicial del cliente
            try:
                data = await asyncio.wait_for(reader.read(4096), timeout=8)
                if not data:
                    return
            except asyncio.TimeoutError:
                print(f"[TIMEOUT] {peer} no envio payload inicial")
                return
            except Exception:
                return

            # Responder 200 OK
            writer.write(HEAD.encode())
            await writer.drain()

            # Conectar al SSH / destino local
            target_reader, target_writer = await asyncio.wait_for(
                asyncio.open_connection(TARGET_HOST, TARGET_PORT),
                timeout=15
            )

            ssh_sock = target_writer.get_extra_info("socket")
            if ssh_sock:
                tune_socket(ssh_sock)

            # Enviar al SSH lo que llegó después de la cabecera HTTP
            # Esto evita perder datos iniciales si vienen pegados al payload.
            # Normalmente SSH espera su handshake, así que solo hacemos pipe normal.

            up = asyncio.create_task(
                self.pipe(reader, target_writer, f"{peer} CLIENTE->SSH")
            )

            down = asyncio.create_task(
                self.pipe(target_reader, writer, f"{peer} SSH->CLIENTE")
            )

            done, pending = await asyncio.wait(
                [up, down],
                timeout=TIMEOUT,
                return_when=asyncio.FIRST_COMPLETED
            )

            for task in pending:
                task.cancel()

        except asyncio.TimeoutError:
            print(f"[TIMEOUT] {peer} conexion inactiva")

        except ConnectionResetError:
            print(f"[RESET] {peer} conexion reseteada")

        except Exception as e:
            print(f"[ERR {peer}] {e}")

        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

            if target_writer:
                try:
                    target_writer.close()
                    await target_writer.wait_closed()
                except Exception:
                    pass

            async with self.lock:
                self.clients -= 1
                if self.clients < 0:
                    self.clients = 0

            print(f"[-] {peer} desconectado ({self.clients})")

    async def pipe(self, reader, writer, label):
        try:
            while True:
                data = await asyncio.wait_for(reader.read(BUFFER_SIZE), timeout=TIMEOUT)

                if not data:
                    break

                writer.write(data)
                await writer.drain()

        except asyncio.TimeoutError:
            print(f"[TIMEOUT PIPE] {label}")

        except ConnectionResetError:
            print(f"[RESET PIPE] {label}")

        except Exception:
            pass

    async def run(self):
        server = await asyncio.start_server(
            self.handle_client,
            LISTEN_HOST,
            LISTEN_PORT,
            reuse_address=True,
            backlog=BACKLOG
        )

        print(f"""
HTTP 200 Proxy — ASYNCIO ESTABLE
✔ Listen: {LISTEN_HOST}:{LISTEN_PORT}
✔ Target: {TARGET_HOST}:{TARGET_PORT}
✔ Clientes globales: {MAX_CLIENTS}
✔ Timeout: {TIMEOUT}s
✔ Backlog: {BACKLOG}
✔ Buffer: {BUFFER_SIZE // 1024} KB
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
