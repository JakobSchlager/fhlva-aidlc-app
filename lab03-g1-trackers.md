# What did we manage to do during the lab?
Jakob Schlager:
Stefan Kastenhofer: Fixed some issues at local service startup. Executed all the load tests locally. 
Pascal Stadler: 

# Load Test Outcomes
- The load test "newcomers" breached the SLO. 
- After completing "newcomers" and immediately starting "gate", it also crossed the threshold 'http_req_failed'. Waiting some time and restarting "gate" resulted in a clean run. 

# Which issues did we encounter?
- Startup Errors because of wrongly generated private key file. File started with " -----BEGIN RSA PRIVATE KEY-----", which could not be parsed correctly. This issue came from the openssl windows tool. When using the wsl openssl command the correct header and footer for the key file were generated. 

