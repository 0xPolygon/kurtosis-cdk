*** ZkEVM Contracts Caching Solution

We manually build zkevm contracts images to make the deployment of the Kurtosis package as fast as possible.

Indeed, most of the deployment time is spent downloading npm dependencies and compiling the zkevm contracts.

We maintain a list of images at [[https://hub.docker.com/r/leovct/zkevm-contracts][leovct/zkevm-contracts]] for fork ids 6, 7, 8 and 9.

If you wish to use a custom image, you can build your own using the /Dockerfile/. All you need to modify is the /zkevm_contracts_image/ field in /params.yml/.

You can follow the steps and manually build and push the different zkevm contract images to your preferred registry, or you can simply trigger this [[https://github.com/leovct/zkevm-contracts/actions/workflows/build-zkevm-contracts-images.yml][workflow]].

#+begin_src bash
docker login
docker buildx create --name container --driver=docker-container
./docs/zkevm-contracts-images-builder.sh $USER
#+end_src
