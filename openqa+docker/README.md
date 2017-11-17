Build with:

```
docker build -t openqa .
```

Run with:

```
docker run -d --cap-add NET_ADMIN -p 80:80 --name mycontainer openqa
```

Run devel version with:

```
docker run -d --cap-add NET_ADMIN -p 80:80 -v /home/acarvajal/git/openQA:/usr/share/openqa --name mycontainer openqa
```

