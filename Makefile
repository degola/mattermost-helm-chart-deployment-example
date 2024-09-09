default: prepare install-postgresql install-s3-credentials-secret install-mattermost
# your own cluster name on which to install Mattermost (check your kubectl config if necessary)
CLUSTER := YOUR_CLUSTER_NAME
# your namespace you want to install Mattermost into
NAMESPACE := YOUR_TARGET_MATTERMOST_NAMESPACE
# Mattermost Kubernetes installation comes with an operator which just needs to get installed once
# You can use a different namespace for the operator if you want
OPERATOR_NAMESPACE := $(NAMESPACE)
# I like to install Postgres for each individual mattermost installation but you can use one single Psotgres instance with
# multiple databases and accounts if you want. Just don't run make install-postgresql in this case
# Postgres root password to create a new user and database for Mattermost
POSTGRES_ROOT_PASSWORD := YOUR_POSTGRES_ROOT_PASSWORD
# Postgres user for the Mattermost installation
POSTGRES_USER := YOUR_DESIRED_MOSTGRES_MATTERMOST_USER
# Postgres password for the Mattermost installation
POSTGRES_PASSWORD := YOUR_DESIRED_MOSTGRES_MATTERMOST_USER
# Postgres database for the Mattermost installation
POSTGRES_DATABASE := mattermost
# Minio (or AWS) S3 Endpoint Host, the S3 endpoint is used for user uploads and other file storage
MINIO_S3_HOST := YOUR_MINIO_S3_ENDPOINT_HOST
MINIO_ACCESS_KEY := YOUR_MINIO_S3_ACCESS_KEY
MINIO_SECRET_KEY := YOUR_MINIO_S3_SECRET_KEY
MINIO_BUCKET := YOUR_MINIO_S3_BUCKET

# The mattermost version, adjust here and run install-mattermost if you want to upgrade
MATTERMOST_VERSION := 9.9.1
# The Ingress Hostname for your Mattermost installation, I'm using a reverse proxy to route traffic to the correct service,
# you may want to change/adjust this to your needs in mattermost-installation.yml
MATTERMOST_HOST := YOUR_MATTERMOST_HOSTNAME

prepare:
	echo "preparing cluster..."
	kubectl config use-context $(CLUSTER)
	kubectl create namespace $(NAMESPACE) || true
	kubectl config set-context --current --cluster=$(CLUSTER) --namespace=$(NAMESPACE)

	helm repo add mattermost https://helm.mattermost.com
	helm repo add bitnami https://charts.bitnami.com/bitnami
	helm repo update

	kubectl create namespace $(OPERATOR_NAMESPACE) || true
	helm install mattermost-operator mattermost/mattermost-operator --namespace $(OPERATOR_NAMESPACE) -f operator-config.yml

install-postgresql:
	kubectl -n $(NAMESPACE) \
		create secret generic postgresql-credentials-mattermost \
		--from-literal=POSTGRES_DB="$(POSTGRES_DATABASE)" \
		--from-literal=POSTGRES_USER="$(POSTGRES_USER)" \
		--from-literal=POSTGRES_PASSWORD="$(POSTGRES_PASSWORD)" \
		--from-literal=DB_CONNECTION_STRING="postgres://$(POSTGRES_USER):$(POSTGRES_PASSWORD)@postgres-mattermost.$(NAMESPACE).svc.cluster.local:5432/$(POSTGRES_DB)?sslmode=disable&connect_timeout=10"

	kubectl -n $(NAMESPACE) apply -f postgresql.yml

install-s3-credentials-secret:
	kubectl -n $(NAMESPACE) delete secret  generic s3-credentials-mattermost || true
	kubectl -n $(NAMESPACE) create secret generic s3-credentials-mattermost \
        --from-literal=URL="https://$(MINIO_S3_HOST)" \
        --from-literal=accesskey="$(MINIO_ACCESS_KEY)" \
        --from-literal=secretkey="$(MINIO_SECRET_KEY)" \
        --from-literal=BUCKET="$(MINIO_BUCKET)"

install-mattermost:
	kubectl config use-context $(CLUSTER)
	kubectl config set-context --current --cluster=$(CLUSTER) --namespace=$(NAMESPACE)
	kubectl apply -f mattermost-license-secret.yml

	MATTERMOST_VERSION=$(MATTERMOST_VERSION) \
	MINIO_BUCKET=$(MINIO_BUCKET) \
	MINIO_S3_HOST=$(MINIO_S3_HOST) \
	MATTERMOST_HOST=$(MATTERMOST_HOST) \
	envsubst <mattermost-installation.yml | kubectl apply -f -

uninstall:
	kubectl config use-context $(CLUSTER)
	kubectl config set-context --current --cluster=$(CLUSTER) --namespace=$(NAMESPACE)

	kubectl -n $(NAMESPACE) delete secret postgresql-credentials-mattermost || true
	kubectl -n $(NAMESPACE) delete secret s3-credentials-mattermost || true
	kubectl -n $(NAMESPACE) delete secret mattermost-license || true

	kubectl -n $(NAMESPACE) delete -f mattermost-installation.yml || true
	kubectl -n $(NAMESPACE) delete -f postgresql.yml || true

uninstall-operator:
	helm uninstall mattermost-operator mattermost/mattermost-operator --namespace $(OPERATOR_NAMESPACE) || true
