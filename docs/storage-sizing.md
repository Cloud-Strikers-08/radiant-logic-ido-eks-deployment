# Radiant Logic IDO 3.1.0 - Storage Sizing

Source: Radiant Logic official self-managed installation guide.

## Default persistent volume sizes

| Component | Size |
|---|---:|
| Keycloak database data | 32Gi |
| Keycloak database WAL | 32Gi |
| etcd | 32Gi |
| Analytics database data | 128Gi |
| Analytics database WAL | 32Gi |
| Observation database data | 128Gi |
| Observation database WAL | 32Gi |
| Portal logs | 16Gi |
| Other components | 56Gi |
| Identity Data Management | 50Gi |
| Total calculated | 538Gi |

Vendor evaluation estimate: approximately 550Gi.

## EKS Storage Configuration

- Storage class: gp3
- Provisioner: ebs.csi.aws.com
- Encryption: enabled
- Volume expansion: enabled
- Volume binding: WaitForFirstConsumer
- Reclaim policy: Delete

PVCs will be provisioned dynamically by the Helm charts.

Do not manually create application PVCs without reviewing
the chart values first.
