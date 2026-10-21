FROM python:3.12-slim-bookworm@sha256:34386ef0cb081344d7ec1c103ba398e6e9f64e9ab3a1509accc92a4e24a07258
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends clamav-daemon clamav-freshclam && rm -rf /var/lib/apt/lists/* && mkdir -p /run/clamav && chown clamav:clamav /run/clamav /var/lib/clamav
COPY deploy/clamd.conf /etc/clamav/clamd.conf
EXPOSE 3310
HEALTHCHECK --interval=30s --timeout=5s --start-period=10m CMD python -c "import socket; s=socket.create_connection(('127.0.0.1',3310),timeout=3); s.sendall(b'zPING\0'); assert s.recv(32).startswith(b'PONG')"
CMD ["sh","-c","freshclam && freshclam -d && exec clamd --foreground=true"]
