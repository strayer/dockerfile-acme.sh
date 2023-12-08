FROM alpine:3.19 AS install

ARG ACME_SH_GIT_REF=130e8dbd40b71a33dfb8adec7a7a681c2059a7a7

RUN apk add --no-cache git curl bash openssl

WORKDIR /

RUN git clone https://github.com/acmesh-official/acme.sh.git acme.sh-git

WORKDIR /acme.sh-git

RUN git checkout "$ACME_SH_GIT_REF"

RUN CA_HOME=/data/ca ./acme.sh --install --home /acme.sh --cert-home /data/certs --no-cron --no-profile && rm /acme.sh/account.conf

FROM alpine:3.19

RUN apk upgrade --no-cache

RUN apk add --no-cache curl bash openssl

ENV CERT_HOME /data/certs
ENV CA_HOME /data/ca
ENV LE_WORKING_DIR /acme.sh
ENV HTTP_HEADER /data/http.header
ENV ACCOUNT_CONF_PATH /data/account.conf

RUN adduser -h / -s /bin/bash -D -H -u 1000 acme

COPY --from=install --chown=acme:0 /acme.sh /acme.sh

RUN mkdir /data && chown acme /data && \
  mkdir $CERT_HOME && chown acme $CERT_HOME && \
  mkdir $CA_HOME && chown acme $CA_HOME

RUN ln -s /acme.sh/acme.sh /usr/local/bin/

COPY cron.sh /usr/local/bin/cron

USER acme

CMD ["/bin/bash"]
