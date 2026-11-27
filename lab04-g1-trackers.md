# What did we manage to do during the lab?
Jakob Schlager: 
Stefan Kastenhofer:  
Pascal Stadler: First setup run failed with 
```
WARNING: Rolling tag detected (bitnami/postgres-exporter:latest), please note that it is strongly recommended to avoid using rolling tags in a production environment.
+info https://techdocs.broadcom.com/us/en/vmware-tanzu/bitnami-secure-images/bitnami-secure-images/services/bsi-doc/apps-tutorials-understand-rolling-tags-containers-index.html
WARNING: Rolling tag detected (bitnami/os-shell:latest), please note that it is strongly recommended to avoid using rolling tags in a production environment.
+info https://techdocs.broadcom.com/us/en/vmware-tanzu/bitnami-secure-images/bitnami-secure-images/services/bsi-doc/apps-tutorials-understand-rolling-tags-containers-index.html

WARNING: There are "resources" sections in the chart not set. Using "resourcesPreset" is not recommended for production. For production installations, please set the following values according to your workload needs:
  - readReplicas.resources
+info https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/
FATAL:  terminating connection due to administrator command
server closed the connection unexpectedly
        This probably means the server terminated abnormally
        before or while processing the request.
connection to server was lost
command terminated with exit code 2
```

Maven blocks FH IP
Your ip has exceeded rate limits. Find out more here https://central.sonatype.org/faq/429-error/

The SLO is too loose -> Needed to decrease p95 from 200 to 20 (or p99 < 100)

Achieved rollback with new SLOs