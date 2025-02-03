ENCLAVE=cdk

kurtosis run --enclave $ENCLAVE . '{
    "args": {
        "l1_engine": "anvil",
    }
}'
