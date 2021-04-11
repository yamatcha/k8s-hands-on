KUBERNETES_VERSION := 1.20.2
KIND_VERSION := 0.10.0
KUSTOMIZE_VERSION := 3.8.7
ARGOCD_VERSION := 2.0.0
VM_OPERATOR_VERSION := 0.12.2
GRAFANA_OPERATOR_VERSION := 3.9.0
KUBE_STATE_METRICS_VERSION := 2.0.0-rc.1

OS = $(shell go env GOOS)
ARCH = $(shell go env GOARCH)

BINDIR = $(PWD)/bin
KUBECTL = $(BINDIR)/kubectl
KUSTOMIZE = $(BINDIR)/kustomize
ARGOCD = $(BINDIR)/argocd
KIND = $(BINDIR)/kind

KIND_CLUSTER_NAME=neco

all: help

.PHONY: launch-k8s
launch-k8s: $(KIND) ## Launch Kubernetes cluster with kind
	if [ ! "$(shell kind get clusters | grep $(KIND_CLUSTER_NAME))" ]; then \
		$(KIND) create cluster --name=$(KIND_CLUSTER_NAME) --config kind-config.yaml --image kindest/node:v$(KUBERNETES_VERSION) --wait 180s; \
	fi

.PHONY: shutdown-k8s
shutdown-k8s: $(KIND) ## Shutdown Kubernetes cluster
	if [ "$(shell kind get clusters | grep $(KIND_CLUSTER_NAME))" ]; then \
		$(KIND) delete cluster --name=$(KIND_CLUSTER_NAME) || true; \
	fi

.PHONY: deploy-argocd
deploy-argocd: $(KUBECTL) ## Deploy argocd on Kubernetes cluster
	$(KUBECTL) create namespace argocd
	$(KUBECTL) apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v$(ARGOCD_VERSION)/manifests/install.yaml



.PHONY: setup
setup: $(KUBECTL) $(KUSTOMIZE) $(ARGOCD) $(KIND) ## Setup tools

$(KUBECTL): ## Install kubectl
	mkdir -p $(BINDIR)
	curl -sfL https://storage.googleapis.com/kubernetes-release/release/v$(KUBERNETES_VERSION)/bin/$(OS)/$(ARCH)/kubectl -o $(KUBECTL)
	chmod 755 $(KUBECTL)

$(KUSTOMIZE): ## Install kustomize
	mkdir -p $(BINDIR)
	curl -sSLf https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize/v$(KUSTOMIZE_VERSION)/kustomize_v$(KUSTOMIZE_VERSION)_$(OS)_$(ARCH).tar.gz | tar -xz -C $(BINDIR)

$(ARGOCD): ## Install argocd-cli
	mkdir -p $(BINDIR)
	curl -sSLf https://github.com/argoproj/argo-cd/releases/download/v$(ARGOCD_VERSION)/argocd-$(OS)-$(ARCH) -o $(ARGOCD)
	chmod 755 $(ARGOCD)

$(KIND): ## Install kind
	mkdir -p $(BINDIR)
	$(call go-install-tool,$(KIND),sigs.k8s.io/kind@v$(KIND_VERSION))

.PHONY: update-vm-operator
update-vm-operator:
	rm -rf manifests/monitoring/victoriametrics/release
	curl -sSLf https://github.com/VictoriaMetrics/operator/releases/download/v$(VM_OPERATOR_VERSION)/bundle_crd.zip -o /tmp/bundle_crd.zip
	unzip /tmp/bundle_crd.zip -d manifests/monitoring/victoriametrics/

.PHONY: update-grafana-operator
update-grafana-operator:
	rm -rf /tmp/grafana-operator
	cd /tmp; git clone --depth 1 -b v$(GRAFANA_OPERATOR_VERSION) https://github.com/integr8ly/grafana-operator
	rm -rf manifests/monitoring/grafana/upstream
	cp -r /tmp/grafana-operator/deploy manifests/monitoring/grafana/upstream
	rm -rf /tmp/grafana-operator

.PHONY: update-kube-state-metrics
update-kube-state-metrics:
	rm -rf /tmp/kube-state-metrics
	cd /tmp; git clone --depth 1 -b v$(KUBE_STATE_METRICS_VERSION) https://github.com/kubernetes/kube-state-metrics
	rm -f manifests/monitoring/kube-state-metrics/upstream/*
	cp /tmp/kube-state-metrics/examples/standard/* manifests/monitoring/kube-state-metrics/upstream
	rm -rf /tmp/kube-state-metrics

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: clean
clean: ## Clean tools
	rm -rf $(BINDIR)

define go-install-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
GOBIN=$(BINDIR) go install $(2) ;\
rm -rf $$TMP_DIR ;\
}
endef