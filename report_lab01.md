# What does beer-tracking-service do?
The Beer Tracking Service is a CRUD service for recording beer consumption. It provides a REST API for creating, reading, updating, and deleting consumption entries. Each entry can include the beer name, volume, alcohol-by-volume (ABV) percentage, and timestamp, and is associated with the authenticated user's account.

It also provides internal endpoints for other services, such as the health-notification-service and statistics-service, to retrieve consumption data. These endpoints are protected by an internal API key and are not exposed through the public API gateway.

Architecturally, it is a layered application consisting of a controller layer (handling HTTP requests), a service layer (containing business logic, including calculating standard drinks), and a repository layer (interacting with the database).

# What did we manage to do during the lab?
Jakob Schlager: Completed the local deployment with Podman Compose and deployed the application to Minikube.

# Which issues did we encounter?
- Image-pull rate limits interrupted deployment during the lab.
- The Podman setup encountered an `nftables` compatibility issue with WSL versions earlier than 2.7.5 (see [Podman issue #25201](https://github.com/podman-container-tools/podman/issues/25201)).
