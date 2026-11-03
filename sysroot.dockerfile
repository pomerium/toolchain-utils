FROM ubuntu:20.04 AS build

RUN apt update
RUN mkdir -p /sysroot/usr/lib /sysroot/usr/lib64 /sysroot/usr/bin \
 && ln -rs /sysroot/usr/lib /sysroot/lib \
 && ln -rs /sysroot/usr/lib64 /sysroot/lib64 \
 && ln -rs /sysroot/usr/bin /sysroot/bin \
 && mkdir /staging \
 && cd /staging \
 && apt download libc-dev-bin libcrypt-dev libcrypt1 linux-libc-dev libc6-dev libc6 \
 && for f in $(find . -name '*.deb'); do dpkg-deb --fsys-tarfile $f > $f.tar; done \
 && for f in $(find . -name '*.tar'); do tar -x --keep-directory-symlink -C /sysroot -f $f; done \
 && rm -rf /sysroot/usr/share \
 && cd /sysroot \
 && for f in $(find "usr/lib/$(uname -m)-linux-gnu/" -type l -lname "/lib/$(uname -m)-linux-gnu/*"); do \
      target="$(basename $(readlink "$f"))"; rm "$f" && ln -s "$target" "$f"; \
    done \
 && for f in $(find "usr/lib64/" -type l -lname "/lib/$(uname -m)-linux-gnu/*"); do \
      target="$(readlink "$f")"; arch="$(uname -m)"; rm "$f" && ln -s "..${target}" "$f"; \
    done
RUN absolute="$(find /sysroot -type l -lname "/*")"; test -z "$absolute" && exit 0 || echo "$absolute"; exit 1
RUN broken="$(find /sysroot -xtype l)"; test -z "$broken" && exit 0 || echo "$broken"; exit 1

FROM scratch

COPY --from=build /sysroot /