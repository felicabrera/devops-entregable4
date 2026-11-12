# Arquitectura

## Componentes

```mermaid
flowchart LR
    subgraph Cliente
        U[Navegador]
    end

    subgraph Ingreso["Ingreso (prod: APISIX *.reto-ucu.net / dev: LoadBalancer de Docker Desktop)"]
        R[ApisixRoute o Service LoadBalancer]
    end

    subgraph NS["Namespace del release (Helm chart notes)"]
        F[frontend<br/>nginx-unprivileged<br/>sirve el sitio y proxea /api]
        B[backend x2<br/>FastAPI + uvicorn<br/>/notes /stats /health /metrics]
        H[(Service headless<br/>un registro A por pod)]
        P[Prometheus<br/>dns_sd sobre el headless<br/>reglas de alerta]
        G[Grafana<br/>datasource y dashboard<br/>aprovisionados]
        NP[NetworkPolicy<br/>solo pods del release llegan al backend]
    end

    subgraph Cluster["Controles del cluster (dev)"]
        K[Kyverno<br/>5 ValidatingPolicy CEL]
        FA[Falco<br/>DaemonSet eBPF + reglas propias]
    end

    U -->|HTTPS / HTTP| R
    R --> F
    R --> G
    R --> P
    F -->|/api/* -> :8000| B
    B --- H
    P -->|scrape /metrics cada 5 s| H
    G -->|PromQL| P
    K -. admision de pods y deployments .-> NS
    FA -. syscalls de los contenedores .-> B
```

## Flujo de entrega

```mermaid
flowchart LR
    Dev[git push main] --> GH[GitHub Actions]
    Dev --> J[Jenkins local<br/>scripts/start-jenkins.sh]

    subgraph GH[GitHub Actions]
        CI[CI: ruff, pytest, hadolint,<br/>shellcheck, helm lint,<br/>kube-linter, kyverno test,<br/>linter del Jenkinsfile]
        SEC[Seguridad: Semgrep, Snyk,<br/>pip-audit, Trivy imagen y config<br/>SARIF a Code Scanning]
        CD[CD: build amd64, Trivy,<br/>push a GHCR, helm upgrade,<br/>helm test, smoke test, rollback]
    end

    subgraph J[Jenkins]
        S1[Checkout] --> S2[Semgrep] --> S3[Snyk] --> S4[Build y test] --> S5[Imagen Docker] --> S6[Trivy] --> S7[Publicar] --> S8[Helm deploy] --> S9[helm test]
    end

    CD -->|ghcr.io/felicabrera/devops-entregable4| REG[(GHCR)]
    REG --> PROD[Cluster UCU<br/>namespace alumno-team9]
    S8 --> DEV[Docker Desktop<br/>namespace notes]
```

## Decisiones

| Tema | Decision | Motivo |
|---|---|---|
| Descubrimiento de targets | `dns_sd_configs` sobre un Service headless | En el cluster de la facultad la cuenta del equipo no puede crear Roles, asi que Prometheus no puede usar `kubernetes_sd_configs`. El headless publica un registro A por pod y cada replica queda como target propio sin RBAC. |
| Exposicion en prod | `ApisixRoute` con hosts `*-team9.reto-ucu.net` | El namespace tiene `services.loadbalancers: 0` y el cluster usa ingress-apisix con certificado wildcard. |
| Exposicion en dev | Services `LoadBalancer` | Docker Desktop los publica en `localhost` sin ingress controller. |
| Politicas de Kyverno | `ValidatingPolicy` (CEL) | Kyverno 1.20 ya no ejecuta `ClusterPolicy` (kyverno.io/v1). Las politicas se escriben una sola vez en CEL y se prueban con `kyverno test` y `kyverno apply` sobre los manifiestos renderizados. |
| Kyverno y Falco en prod | No se instalan | Necesitan CRDs, ClusterRoles y DaemonSets privilegiados; la cuenta del equipo solo tiene permisos de namespace. Se validan en el cluster local y en CI. |
| Datos de las notas | `emptyDir` por pod | La app guarda un JSON por proceso (como en los entregables anteriores). Dos replicas no comparten notas; es suficiente para el laboratorio y queda documentado como mejora. |
| Imagenes | Multi-stage, Debian slim y nginx-unprivileged | Ver `reports/image-analysis.md`. |
