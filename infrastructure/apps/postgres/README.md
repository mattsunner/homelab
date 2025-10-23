# PostgreSQL and PgAdmin Setup

This directory contains the configuration for a shared PostgreSQL database instance and PgAdmin web interface for the homelab.

## Architecture

- **PostgreSQL 16 (Alpine)**: Single StatefulSet with persistent storage via Longhorn
- **PgAdmin 4**: Web-based database administration interface
- **Storage**: Longhorn distributed storage with 10GB for PostgreSQL, 2GB for PgAdmin
- **Access**: PgAdmin accessible at `https://pgadmin.mattsunner.com`

## Components

### PostgreSQL StatefulSet
- **Image**: `postgres:16-alpine`
- **Replicas**: 1 (single node, can be scaled later)
- **Storage**: 10GB Longhorn PersistentVolume
- **Resources**: 256Mi-1Gi RAM, 250m-1000m CPU
- **Services**:
  - `postgresql` (headless) - for StatefulSet
  - `postgresql-lb` (ClusterIP) - for application connections

### PgAdmin Deployment
- **Image**: `dpage/pgadmin4:latest`
- **Storage**: 2GB Longhorn PersistentVolume
- **Resources**: 256Mi-512Mi RAM, 100m-500m CPU
- **Ingress**: HTTPS with Let's Encrypt TLS certificate
- **Pre-configured server**: Points to `postgresql-lb` service

## Deployment Instructions

### Step 1: Install Longhorn (if not already installed)

Longhorn is required for persistent storage. It will be deployed automatically via ArgoCD.

### Step 2: Create Secrets

**IMPORTANT:** These secrets must be created manually before deploying PostgreSQL and PgAdmin.

```bash
# PostgreSQL credentials (choose a strong password!)
kubectl create secret generic postgresql-secret \
  --namespace postgres \
  --from-literal=postgres-user=postgres \
  --from-literal=postgres-password=YOUR_STRONG_PASSWORD_HERE

# PgAdmin credentials (choose your email and password)
kubectl create secret generic pgadmin-secret \
  --namespace postgres \
  --from-literal=pgadmin-email=admin@mattsunner.com \
  --from-literal=pgadmin-password=YOUR_PGADMIN_PASSWORD_HERE
```

**Security Notes:**
- Use strong, unique passwords (20+ characters recommended)
- These secrets are NOT stored in Git (they're created manually on the cluster)
- Store passwords securely in a password manager
- Never commit secrets to version control

### Step 3: Configure DNS

Add DNS record in Cloudflare:

| Name | Type | Content | Proxy Status | TTL |
|------|------|---------|--------------|-----|
| pgadmin | A | 100.121.16.66 | DNS only | Auto |
| longhorn | A | 100.121.16.66 | DNS only | Auto |

### Step 4: Commit and Push

```bash
cd /path/to/homelab
git add infrastructure/
git commit -m "Add PostgreSQL and PgAdmin infrastructure"
git push
```

ArgoCD will automatically:
1. Install Longhorn storage system
2. Create the `postgres` namespace
3. Deploy PostgreSQL StatefulSet with persistent storage
4. Deploy PgAdmin with persistent storage
5. Create ingress resources
6. Request TLS certificates from Let's Encrypt

### Step 5: Verify Deployment

```bash
# Check Longhorn installation
kubectl get pods -n longhorn-system

# Check PostgreSQL
kubectl get pods -n postgres
kubectl get pvc -n postgres
kubectl get svc -n postgres

# Check PgAdmin
kubectl logs -n postgres deployment/pgadmin

# Check certificates
kubectl get certificate -n postgres
kubectl get certificate -n longhorn-system

# Test PostgreSQL connection
kubectl run -it --rm psql-test --image=postgres:16-alpine --restart=Never -n postgres -- \
  psql -h postgresql-lb -U postgres -c "SELECT version();"
```

### Step 6: Access PgAdmin

1. Navigate to: `https://pgadmin.mattsunner.com`
2. Login with the email and password from `pgadmin-secret`
3. The PostgreSQL server should be pre-configured as "Homelab PostgreSQL"
4. Connect using the password from `postgresql-secret`

## Using PostgreSQL with Applications

### Connection Details for Apps

Applications should connect to PostgreSQL using:

```yaml
# In your application deployment
env:
- name: DB_HOST
  value: "postgresql-lb.postgres.svc.cluster.local"
- name: DB_PORT
  value: "5432"
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: <app-specific-secret>
      key: db-user
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: <app-specific-secret>
      key: db-password
- name: DB_NAME
  value: "<app-database-name>"
```

### Creating a New Database for an Application

1. **Via PgAdmin:**
   - Navigate to `https://pgadmin.mattsunner.com`
   - Right-click on "Homelab PostgreSQL" → Create → Database
   - Name: `myapp_db`
   - Owner: `postgres` (or create a dedicated user)

2. **Via kubectl:**
   ```bash
   kubectl exec -it postgresql-0 -n postgres -- \
     psql -U postgres -c "CREATE DATABASE myapp_db;"
   ```

3. **Create dedicated user (recommended for security):**
   ```bash
   # Create user
   kubectl exec -it postgresql-0 -n postgres -- \
     psql -U postgres -c "CREATE USER myapp_user WITH PASSWORD 'strong_password_here';"

   # Grant permissions
   kubectl exec -it postgresql-0 -n postgres -- \
     psql -U postgres -c "GRANT ALL PRIVILEGES ON DATABASE myapp_db TO myapp_user;"

   # Create secret for the app
   kubectl create secret generic myapp-db-secret \
     --namespace <app-namespace> \
     --from-literal=db-user=myapp_user \
     --from-literal=db-password=strong_password_here \
     --from-literal=db-name=myapp_db
   ```

## Security Best Practices

### Network Security
- PostgreSQL is only accessible within the cluster (ClusterIP service)
- No external exposure of PostgreSQL port 5432
- PgAdmin accessible only via Tailscale network
- TLS encryption for PgAdmin ingress

### Authentication
- Use dedicated database users per application
- Grant minimal required privileges (GRANT specific permissions, not ALL)
- Rotate passwords regularly
- Consider implementing connection pooling (PgBouncer) for production workloads

### Backup Strategy

**IMPORTANT:** Currently, there is no automated backup configured. Recommended solutions:

1. **Longhorn Snapshots:**
   ```bash
   # Access Longhorn UI at https://longhorn.mattsunner.com
   # Configure recurring snapshots for postgresql-data volume
   ```

2. **PostgreSQL Logical Backups (pg_dump):**
   ```bash
   # Create CronJob for automated backups
   kubectl create cronjob pg-backup --schedule="0 2 * * *" \
     --image=postgres:16-alpine -n postgres -- \
     /bin/sh -c "pg_dump -h postgresql-lb -U postgres > /backup/backup-$(date +%Y%m%d).sql"
   ```

3. **Consider Velero** for full cluster backups (future enhancement)

### Storage Management

```bash
# Check PostgreSQL storage usage
kubectl exec -it postgresql-0 -n postgres -- df -h /var/lib/postgresql/data

# Check PgAdmin storage usage
kubectl exec -it deployment/pgadmin -n postgres -- df -h /var/lib/pgadmin

# Resize volume if needed (Longhorn supports online expansion)
kubectl patch pvc postgresql-data-postgresql-0 -n postgres \
  -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

## Troubleshooting

### PostgreSQL won't start

```bash
# Check pod status
kubectl describe pod postgresql-0 -n postgres

# Check logs
kubectl logs postgresql-0 -n postgres

# Common issues:
# 1. PVC not bound - check Longhorn is running
# 2. Secrets missing - verify postgresql-secret exists
# 3. Resource limits - check node resources
```

### PgAdmin connection issues

```bash
# Check PgAdmin logs
kubectl logs deployment/pgadmin -n postgres

# Test PostgreSQL connectivity from PgAdmin pod
kubectl exec -it deployment/pgadmin -n postgres -- \
  nc -zv postgresql-lb 5432

# Reset PgAdmin data (CAUTION: deletes saved connections and preferences)
kubectl delete pvc pgadmin-data -n postgres
kubectl rollout restart deployment/pgadmin -n postgres
```

### Certificate not issuing

```bash
# Check certificate status
kubectl describe certificate pgadmin-tls -n postgres

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Common fix: verify DNS is propagated
dig pgadmin.mattsunner.com
```

### Database connection refused

```bash
# Verify PostgreSQL is running
kubectl get pods -n postgres

# Test connection from another pod
kubectl run -it --rm psql-test --image=postgres:16-alpine --restart=Never -n postgres -- \
  psql -h postgresql-lb -U postgres -c "\l"

# Check service endpoints
kubectl get endpoints -n postgres
```

## Monitoring

PostgreSQL metrics are exposed to Prometheus (via the monitoring stack):

```bash
# Port-forward to see metrics
kubectl port-forward postgresql-0 -n postgres 5432:5432

# Query via Grafana at https://grafana.mattsunner.com
# Import PostgreSQL dashboard (Grafana ID: 9628)
```

## Maintenance

### Upgrading PostgreSQL

```bash
# Update image version in postgresql-statefulset.yaml
# Commit and push - ArgoCD will handle the upgrade
# IMPORTANT: Always backup before upgrading!

# Check upgrade status
kubectl rollout status statefulset/postgresql -n postgres
```

### Upgrading PgAdmin

```bash
# PgAdmin uses latest tag - restart to pull new image
kubectl rollout restart deployment/pgadmin -n postgres
```

### Scaling PostgreSQL (Future)

Currently configured for single replica. For HA:
1. Consider PostgreSQL operator (CloudNativePG, Zalando Postgres Operator)
2. Configure streaming replication
3. Ensure Longhorn volume can be replicated

## Access URLs

- **PgAdmin**: https://pgadmin.mattsunner.com
- **Longhorn UI**: https://longhorn.mattsunner.com
- **PostgreSQL** (internal only): `postgresql-lb.postgres.svc.cluster.local:5432`

## File Structure

```
infrastructure/apps/postgres/
├── README.md                      # This file
├── namespace.yaml                 # Namespace definition
├── postgresql-statefulset.yaml    # PostgreSQL StatefulSet and Services
├── pgadmin-deployment.yaml        # PgAdmin Deployment, PVC, Service, ConfigMap
└── pgadmin-ingress.yaml          # PgAdmin Ingress with TLS
```

## Future Enhancements

- [ ] Automated backups with CronJob
- [ ] PostgreSQL metrics exporter for Prometheus
- [ ] Connection pooling with PgBouncer
- [ ] High availability with replicas
- [ ] Database operator for declarative user/database management
- [ ] OAuth2 proxy for PgAdmin authentication
- [ ] Resource quotas and network policies

## Support

For issues:
1. Check PostgreSQL logs: `kubectl logs postgresql-0 -n postgres`
2. Check PgAdmin logs: `kubectl logs deployment/pgadmin -n postgres`
3. Verify secrets exist: `kubectl get secrets -n postgres`
4. Check ArgoCD sync status in ArgoCD UI
