.PHONY: check python-check terraform-check helm-check docker-check

check: python-check terraform-check helm-check docker-check

python-check:
	cd app && poetry install --no-root
	cd app && poetry run black --check prima-tech-challenge
	cd app && poetry run flake8 prima-tech-challenge

terraform-check:
	cd terraform && terraform fmt -check -recursive
	cd terraform && terraform init -backend=false
	cd terraform && terraform validate

helm-check:
	helm lint ./helm/prima-tech-challenge
	helm template prima ./helm/prima-tech-challenge > /dev/null

docker-check:
	docker build -t prima-tech-challenge:ci ./app
