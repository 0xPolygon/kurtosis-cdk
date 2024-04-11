Running Docker on MacOS differs slightly from Docker on Linux and you may encounter some issues. 

## Private IP issues

A key distinction is that Docker on MacOS doesn't directly expose container networks to the host system. Consequently, accessing containers via their private IPs is not possible.

The CDK Kurtosis package requires this functionality to run smoothly. 

Follow the steps below to solve these issues on your MacOS system.

### Set up `docker-mac-net-connect`

1. Install `docker-mac-net-connect`.

    ```sh
    brew install chipmk/tap/docker-mac-net-connect
    ```

2. Start the service and configure it to launch on boot.

    ```sh
    sudo brew services start chipmk/tap/docker-mac-net-connect
    ```

### Uninstall current Docker engine 

Run the following command:

```sh
/Applications/Docker.app/Contents/MacOS/uninstall
```

### Install the latest Docker desktop

Download the software on the [Docker installation page](https://docs.docker.com/desktop/install/mac-install/).

!!! important
    - Make sure you install version 4.27 or higher of the desktop software.
    - This is necessary for running the zkEVM prover on MacOS.

### Test accessing containers with private IPs

1. Start a dummy `nginx` container.

    ```sh
    docker run --rm --name nginx -d nginx
    ```

2. Access the container using its private IP.

    ```sh
    curl -m 1 -I $(docker inspect nginx --format '{{.NetworkSettings.IPAddress}}')
    ```

    You should see output something like this:

    ```sh
    HTTP/1.1 200 OK
    Server: nginx/1.25.4
    Date: Mon, 08 Apr 2024 08:11:30 GMT
    Content-Type: text/html
    Content-Length: 615
    Last-Modified: Wed, 14 Feb 2024 16:03:00 GMT
    Connection: keep-alive
    ETag: "65cce434-267"
    Accept-Ranges: bytes
    ```

Now you can return to the [deploy the CDK instructions](deploy-stack.md#set-up) set up and continue.

## zkEVM docker image issue

If you get issues installing the zkEVM docker image after running the Kurtosis enclave, try running the following, then run it again:

```sh
docker pull --platform linux/amd64 hermeznetwork/zkevm-prover:v6.0.0
```

</br>