.PHONY: check python-check terraform-check helm-check docker-check

check: python-check terraform-check helm-check docker-check

python-check:
	cd app && make python-check

terraform-check:
	cd terraform && make format
	cd terraform && make init
	cd terraform && make validate

helm-check:
	helm lint ./helm/prima-tech-challenge
	helm template prima ./helm/prima-tech-challenge > /dev/null

docker-check:
	docker build -t prima-tech-challenge:ci ./app
