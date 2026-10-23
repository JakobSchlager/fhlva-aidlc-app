# What did we manage to do during the lab?
Jakob Schlager: Worked on the azure deployment. Tried four different locations, but could not finish it yet. Worked on defining SLIs and SLOs.
Stefan Kastenhofer: Worked on the azure deployment. Could not connect to the deployed service. Worked on defining SLIs and SLOs.
Pascal Stadler: Fixed script for azure deployment. Had issues with necessary global unique names for azure resources. Also supported other students regarding their deployment issues. Worked on defining SLIs and SLOs. Create documentation regarding limitations with the predefined metrics & SLI-SLOs regarding response time.

The SLOs are available at: [https://ufr26339.apps.dynatrace.com/ui/apps/dynatrace.dashboards/document/42ed63de-1782-4596-94dc-a86e5b50d889](https://ufr26339.apps.dynatrace.com/ui/apps/dynatrace.dashboards/document/42ed63de-1782-4596-94dc-a86e5b50d889)
SLO documentation: [https://ufr26339.apps.dynatrace.com/ui/document/v0/#share=6fd0e7db-c2d4-4c64-8dca-34cbde4a4569](https://ufr26339.apps.dynatrace.com/ui/document/v0/#share=6fd0e7db-c2d4-4c64-8dca-34cbde4a4569)

# Defined SLIs and SLOs
- Response time of the beer-tracking-service (Both Controller)
  - faster then 500 ms - Changed to 251 and 252 to show limitations of the predefined metrics
  - Target: 99.95%
- Service availability of the beer-tracking-service (Both Controller)
  - Target: 99.95%

# Which issues did we encounter?
- Unable to test locations without running the full azure deployment. Fails only after roughly 20 minutes.
    - "User does not have access to the ressource in azure."
    - "Insufficient VCPU quota."
    - Microsoft Storage: "Subscription not found."
    - Unable to preventatively test regions.
    - Container registry needs unique name.
    - Helm deployment failed due to network issues. (Interrupting automated deployment)
- Docker engine suddenly stopped while deploying. No fix.
- Predefined metrics especially for response time don't work well for SLI definition. As the metrics are automatically aggregated which changes the result and limits the accuracy of the results. For example if a 6 hour timeframe is used for a 30 days SLO query - we have 30*24/6 = 120 data points. This means either the SLO is 100% or 99,167% - which is not accurate enough for a 99.95% SLO. See Notebook: [https://ufr26339.apps.dynatrace.com/ui/document/v0/#share=6fd0e7db-c2d4-4c64-8dca-34cbde4a4569](https://ufr26339.apps.dynatrace.com/ui/document/v0/#share=6fd0e7db-c2d4-4c64-8dca-34cbde4a4569) for details.

