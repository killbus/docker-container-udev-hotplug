FROM balenalib/amd64-alpine:run

# Enable udev for detection of dynamically plugged devices
ENV UDEV=on
ARG DOCKER_VERSION=20.10.3

COPY udev/usb.rules /etc/udev/rules.d/usb.rules

# install docker
RUN set -eux; \
	\
	apkArch="$(apk --print-arch)"; \
	case "$apkArch" in \
		'x86_64') \
			url="https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz"; \
			;; \
		'armhf') \
			url="https://download.docker.com/linux/static/stable/armel/docker-${DOCKER_VERSION}.tgz"; \
			;; \
		'armv7') \
			url="https://download.docker.com/linux/static/stable/armhf/docker-${DOCKER_VERSION}.tgz"; \
			;; \
		'aarch64') \
			url="https://download.docker.com/linux/static/stable/aarch64/docker-${DOCKER_VERSION}.tgz"; \
			;; \
		*) echo >&2 "error: unsupported architecture ($apkArch)"; exit 1 ;; \
	esac; \
	\
	curl -o docker.tgz "$url"; \
	\
	tar --extract \
		--file docker.tgz \
		--strip-components 1 \
		--directory /usr/local/bin/ \
	; \
	rm docker.tgz; \
	\
	docker --version

RUN  find /usr/local/bin/ -type f ! -name docker -exec rm '{}' \;


# Install dependencies
RUN install_packages findmnt util-linux grep

WORKDIR /usr/src
COPY scripts scripts
RUN chmod +x scripts/*

# Change your CMD as needed
CMD [ "balena-idle" ]