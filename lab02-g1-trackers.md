# What did we manage to do during the lab?
Jakob Schlager: Worked on the azure deployment. Tried four different locations, but could not finish it yet. Worked on defining SLIs and SLOs.
Stefan Kastenhofer: Worked on the azure deployment. Could not connect to the deployed service. Worked on defining SLIs and SLOs.

The SLOs are available at: https://ufr26339.apps.dynatrace.com/ui/apps/dynatrace.dashboards/document/42ed63de-1782-4596-94dc-a86e5b50d889

# Which issues did we encounter?
- Unable to test locations without running the full azure deployment. Fails only after roughly 20 minutes.
    - "User does not have access to the ressource in azure."
    - "Insufficient VCPU quota."
    - Microsoft Storage: "Subscription not found."
    - Unable to preventatively test regions.
- Docker engine suddenly stopped while deploying. No fix.

