# What does beer-tracking-service do?
The Beer Tracking Service is a CRUD service for recording beer consumption. It provides a REST API for creating, reading, updating, and deleting consumption entries. Each entry can include the beer name, volume, alcohol-by-volume (ABV) percentage, and timestamp, and is associated with the authenticated user's account.

It also provides internal endpoints for other services, such as the health-notification-service and statistics-service, to retrieve consumption data. These endpoints are protected by an internal API key and are not exposed through the public API gateway.

Architecturally, it is a layered application consisting of a controller layer (handling HTTP requests), a service layer (containing business logic, including calculating standard drinks), and a repository layer (interacting with the database).

# What did we manage to do during the lab?
Jakob Schlager: Completed the local deployment with Podman Compose and deployed the application to Minikube.
Pascal Stadler: Completed the local deployment with docker compose (rancher desktop) and deployed the application to the local rancher desktop Kubernetes cluster. (Added a script to simplify the deployment process.) Added monitoring to local kubernetes cluster with dynatrace. Started deployment to azure (not completed).


# Which issues did we encounter?
- Image-pull rate limits interrupted deployment during the lab.
- Network issues, caused the docker builds to fail at first during the lab.
- Using rancher desktop, the local scripts use the special podman commands instead of the standard docker commands, which required adaptation of the scripts.
- Dynatrace monitoring of the whole azure environment was not possible due to the limited permissions (as the student account is bound to the fhooe organization and can't register a new app).
- The naming of the storage account was an issue, due to naming requirements of azure.
- Unclear resource group documentation - Given scripts and terraform can't handle a different resource group name, which is not documented.
- Long deployment times to azure, especially of the application gateway, which took up to 10 minutes to deploy - limited amount of tries during the lab.
- Set node pool doesn't work, as the specified region seems to have issues with the used VM type.
- The Podman setup encountered an `nftables` compatibility issue with WSL versions earlier than 2.7.5 (see [Podman issue #25201](https://github.com/podman-container-tools/podman/issues/25201)).
