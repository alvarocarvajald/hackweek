# Docker configuration to run openQA on a single container

Steps to test:

* Clone this directory
* Build with:

```
docker build -t openqa .
```

* Run with:

```
docker run -d --cap-add NET_ADMIN -p 80:80 --name mycontainer openqa
```

## Run an openQA development version

Ideally, running an openQA developement version should be as easy as replacing `/usr/share/openqa` with the contents of `git://github.com/os-autoinst/openQA`
within the container, for example, with the following command:

```
docker run -d --cap-add NET_ADMIN -p 80:80 -v /path/to/devel/version/openQA:/usr/share/openqa --name mycontainer openqa
```

Unfortunately, newer versions of openQA have further required packages that may or may not be installed by the Dockerfile in this repository.

As of this document's writing, I have compiled known extra requirements in the file `Dockerfile-devel`, so to use a development version of openQA should require
the above steps to build an `openqa` image, and the following extra steps to build a development version of the docker image:

* Build with:

```
docker build -t openqa-devel -f Dockerfile-devel .
```

* Run with:

```
docker run -d --cap-add NET_ADMIN -p 80:80 -v /path/to/devel/version/openQA:/usr/share/openqa --name mycontainer openqa-devel
```

* Note: the path `/usr/share/openqa/assets/cache` within the container, needs to be writable by user `geekotest`, so be sure to set ownerships/permissions accordingly
to the path outside the container to attain that.

