# argocd-istio-proxypass

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