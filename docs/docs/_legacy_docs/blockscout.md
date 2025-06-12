# Blockscout
Please, refer to [source package README](https://github.com/xavier-romero/kurtosis-blockscout/blob/main/README.md) for further documentation.

# Publish service
If you want to publish Blockscout so it can be remotely accessed, you need to set some additional params to kurtosis-cdk stack, that will be passed to Blockscout package.


- blockscout_public_ip: This is the public IP that will be used to remotely access your Blockscout. If you have any network device NATing your IP, you need to set here the public facing IP address, as that ip address will be used by user's browser to access resources.
- blockscout_public_port: The port for the frontend (UI) that will be exposed by Kurtosis without remapping. That's the port that a remote user needs to type in its browser. 
- blockscout_backend_port: The backend is directly accessed by the browser, so this is the port where backend will be directly exposed by Kurtosis.

Example:
```yaml
args:
    additional_services:
        - blockscout
    blockscout_params:
        blockscout_public_ip: 210.20.30.40
        blockscout_public_port: 8000
        blockscout_backend_port:  8001
```


On the example above, the final URL for remote access would be:

    http://210.20.30.40:8000

You can also set a DNS record instead, example:
```yaml
args:
    additional_services:
        - blockscout
    blockscout_params:
        blockscout_public_ip: blockscout.example.com
        blockscout_public_port: 8000
        blockscout_backend_port:  8001
```

That would result on the service being accessible through

    http://blockscout.example.com:8000


Please note that both ports need to be reachable for the service to work properly. So, from any location that you want to access the service, you need to be sure that you can:
- Reach the configured ip address a.b.c.d (or DNS record)
- Reach the TCP port blockscout_public_port
- Reach the TCP port blockscout_backend_port
