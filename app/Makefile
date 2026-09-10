IMAGE_NAME      ?= prima-tech-challenge
IMAGE_TAG       ?= local
CONTAINER_NAME  ?= prima-api
HOST_PORT       ?= 5000
CONTAINER_PORT  ?= 5000
ENV_FILE        ?= .env
DOCKER_NETWORK  ?= docker-compose_default

IMAGE := $(IMAGE_NAME):$(IMAGE_TAG)

.PHONY: build run rm

build:
	docker build \
		-t $(IMAGE) \
		.

run:
	docker run -d \
		--name $(CONTAINER_NAME) \
		--network $(DOCKER_NETWORK) \
		--env-file $(ENV_FILE) \
		-p $(HOST_PORT):$(CONTAINER_PORT) \
		$(IMAGE)

rm:
	-docker rm -f $(CONTAINER_NAME)