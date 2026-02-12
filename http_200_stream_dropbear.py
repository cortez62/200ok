#!/usr/bin/env python3
import os
import socket, threading, time

LISTEN_HOST = os.getenv("LISTEN_HOST", "0.0.0.0")
LISTEN_PORT = int(os.getenv("LISTEN_PORT", "80"))
TARGET_HOST = os.getenv("TARGET_HOST", "127.0.0.1")
TARGET_PORT = int(os.getenv("TARGET_PORT", "22"))

LISTEN   = (LISTEN_HOST, LISTEN_PORT)
TARGET   = (TARGET_HOST, TARGET_PORT)    # Prueba SSH primero. Si corta, luego te paso dual 22+550
BUFFER   = 65536                # 64KB estable
PAUSE_UP = 0.001                # Control de flujo anti-reset (ajustable)

HEAD = (
    "HTTP/1.1 200 OK\r\n"
    "Server: Stream-Proxy-DrBoa\r\n"
    "Connection: keep-alive\r\n\r\n"
)

def tune(s):
    s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 524288)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 524288)
    s.settimeout(40)

def forward(src, dst, direction):
    while True:
        try:
            data = src.recv(BUFFER)
            if not data: break
            dst.sendall(data)

            # Control de flujo solo en subida 📌 evita corte al 60%
            if direction == "UP":
                time.sleep(PAUSE_UP)

        except Exception:
            break

    try: src.close(); dst.close()
    except: pass


def handle(client, addr):
    try:
        client.recv(4096)  
        client.sendall(HEAD.encode())

        ssh = socket.socket()
        tune(client)
        tune(ssh)
        ssh.connect(TARGET)

        print(f"[+] {addr} conectado → SSH")

        threading.Thread(target=forward, args=(client, ssh, "UP"), daemon=True).start()
        threading.Thread(target=forward, args=(ssh, client, "DOWN"), daemon=True).start()

    except Exception as e:
        print(f"[ERR] {addr}: {e}")
        try: client.close()
        except: pass


def main():
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(LISTEN)
    srv.listen(300)

    print(f"\n🚀 Proxy Optimizado Anti-corte activo en {LISTEN[1]}\n")

    while True:
        c,a = srv.accept()
        threading.Thread(target=handle, args=(c,a), daemon=True).start()


if __name__ == "__main__":
    main()
