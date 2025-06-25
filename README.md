# argocd-istio-proxypass

## Components Overview

### Passthrough Proxy

The Passthrough Proxy is a lightweight HTTP proxy deployed in the service mesh. It intercepts all traffic within the target namespace by leveraging Istio routing. The proxy captures both request and response bodies, applies configurable sampling, and masks sensitive data such as passwords, tokens, and personally identifiable information (PII) using pattern-based redaction. The proxy is designed without an Istio sidecar to avoid routing loops and forwards sanitized traffic data to the Traffic Collector service for storage and analysis.

**Key Features:**
- Intercepts all HTTP traffic in the namespace via Istio VirtualService routing
- Configurable sampling rate to control data volume
- Masks sensitive fields (e.g., SSNs, credit cards, passwords, API keys)
- Forwards captured and sanitized traffic to the Traffic Collector
- Runs without an Istio sidecar to prevent routing loops

### Traffic Collector

The Traffic Collector is a backend service that receives sanitized traffic data from the Passthrough Proxy. It stores captured traffic in memory and on disk, and exposes a REST API for querying captured requests, responses, and traffic statistics. The collector is also deployed without an Istio sidecar to ensure direct communication from the proxy and to avoid mesh routing complications.

**Key Features:**
- Receives and stores sanitized traffic data from the proxy
- Provides REST API endpoints for querying captured traffic and statistics
- Supports both in-memory and persistent file-based storage
- Runs without an Istio sidecar for direct access

---

This architecture enables comprehensive traffic analysis and auditing while maintaining strong data privacy controls, making it suitable for security-sensitive environments.

## Namespace Management: Dev vs. Prod

This project uses ArgoCD Applications to deploy resources into Kubernetes namespaces for both development and production environments.  
A key configuration difference between these environments is how the namespace is managed by ArgoCD, controlled by the `CreateNamespace` sync option.

### Development (`traffic-capture-dev`)

- **Setting:** `CreateNamespace` is **not** set (default behavior).
- **Effect:** ArgoCD will automatically create the `traffic-capture-dev` namespace if it does not exist, and can also delete it if the Application is deleted and pruning is enabled.
- **Use Case:** This is convenient for development and testing, where environments are frequently created and destroyed, and accidental deletion is less risky.

### Production (`traffic-capture-prod`)

- **Setting:** `CreateNamespace=false` is explicitly set in the Application manifest.
- **Effect:** ArgoCD will **not** create or delete the `traffic-capture-prod` namespace. The namespace must be created and managed manually (e.g., by a platform administrator or infrastructure automation).
- **Use Case:** This is a best practice for production to prevent accidental deletion of critical namespaces and to ensure tighter control over the production environment.

### Summary Table

| Environment | CreateNamespace | Namespace Managed By | Risk of Accidental Deletion |
|-------------|----------------|---------------------|----------------------------|
| Dev         | default (true) | ArgoCD              | Higher                     |
| Prod        | false          | Admin/IaC           | Lower                      |

**Recommendation:**  
Keep `CreateNamespace=false` in production for safety, and use the default in development for convenience.