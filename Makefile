SHELL := /bin/zsh
VENV := .venv
PYTHON := $(VENV)/bin/python

.PHONY: bootstrap dev lint test contract-test clean

bootstrap:
	pnpm install
	python3 -m venv $(VENV)
	$(PYTHON) -m pip install --upgrade pip
	$(PYTHON) -m pip install pytest ruff

dev:
	docker compose -f infra/docker/docker-compose.yml up -d
	pnpm dev

lint:
	pnpm lint
	$(PYTHON) -m ruff check services/render-worker

test:
	pnpm test
	$(PYTHON) -m pytest services/render-worker/tests

contract-test:
	pnpm contract-test

clean:
	pnpm clean
	docker compose -f infra/docker/docker-compose.yml down -v
