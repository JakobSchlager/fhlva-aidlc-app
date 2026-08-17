# Pre-requisites
- Azure Account
- Claud Code / GitHub CoPilot / Mistral Student Account
- Node.js and npm installed
- Podman / minikube installed


# Procedure
install openspec:
npm install -g @fission-ai/openspec@latest

cd your-project
openspec init


## initial prompt

Bootstrap a web-based microservice-structured online service, which allows to track beer consumption per person. For frontend-services TypeScript should be used. Backend-services should be implemented in Java. For data storage a PostgreSQL database should be used. 

Microservices to be implemented are:
- a login/authentication service
- the beer tracking service, which we will refine separately
- a health/notification service, warning the user about overconsumption of beer
- a statistics service, which serves general statistics about beer consumption

use /opsx:propose to generate a specification draft

## refinement
refine the created specs to optimize for a target deployment on Azure with Azure Kubernetes Services (AKS)

## apply
/opsx:apply