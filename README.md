# acme.sh in Docker

## What?

An opiniated way to issue certificates with acme.sh in a Docker container and handing them off to other containers/software.

## Why?

The official acme.sh container has a lot of stuff in it I don't need and can't run with `--read-only`. I also don't want to mix implementation details of software using certificates into acme.sh - acme.sh should just care about one thing: Issuing certificates.

## How?

After issuing a certificate, acme.sh installs the certificate files into a certs volume and touches a `reload` file. Other software with priviledged access, e.g. a cronjob on the Docker host, can then trigger actions that reload the certificate in other container that use them.

## Usage

The image is pushed and rebuilt daily if Alpine upgrades are available to the Github container registry: [ghcr.io/strayer/acme.sh](https://github.com/strayer/dockerfile-acme.sh/pkgs/container/acme.sh)

The container expects a volume at /data that will contain the acme.sh state and a volume at /certs that will contain issued certificates. The DNS provider and anything else should be configured by environment variables, see the acme.sh documentation for reference. The `cron` command will run `acme.sh --cron` every 24 hours.

The rest of the documentation is based on this test/development setup:

```sh
# Variables used by following commands in the documentation
export DOMAIN=example.tld
export ALIAS_DOMAIN=alias-example.tld

# DNS API configuration
echo "CF_Token=XXX" > .env
echo "CF_Account_ID=XXX" >> .env
echo "CF_Zone_ID=XXX" >> .env
echo "ACCOUNT_EMAIL=admin@example.tld" >> .env

# Volumes
mkdir data certs

docker run -d \
  --env-file .env \
  --name=acme-sh \
  --read-only \
  -v $(pwd)/data:/data \
  -v $(pwd)/certs:/certs \
  --tmpfs /tmp \
  ghcr.io/strayer/acme.sh:latest \
  cron
```

### Issuing a certificate

Issuing a (staging) certificate is done just as it would be done with the acme.sh CLI itself:

```sh
docker exec acme-sh acme.sh --issue \
  --server letsencrypt \
  --test -d $DOMAIN -d \*.$DOMAIN \
  --keylength ec-384 \
  --dns dns_cf \
  --challenge-alias $ALIAS_DOMAIN
```

After issuing the certificate it should be installed and a file touched that will trigger external service reload/restart:

```sh
mkdir certs/$DOMAIN
docker exec acme-sh acme.sh --install-cert \
  --test -d $DOMAIN -d \*.$DOMAIN \
  --ecc \
  --cert-file /certs/$DOMAIN/cert.pem \
  --key-file /certs/$DOMAIN/key.pem \
  --fullchain-file /certs/$DOMAIN/fullchain.pem \
  --ca-file /certs/$DOMAIN/ca.pem \
  --reloadcmd "touch /certs/$DOMAIN/reload"
```

### Using the certificate in another container

The easiest way for other containers to access the issued certificates is to simply bind mount the domains cert directory directly.

```sh
cat <<EOT > nginx.conf
server {
  listen 443 ssl;
  server_name _;

  ssl_certificate /ssl/fullchain.pem;
  ssl_certificate_key /ssl/key.pem;

  location / {
    add_header Content-Type text/plain;
    return 200 'hello world';
  }
}
EOT
docker run -d --rm -p 8443:443 \
  --name=nginx \
  -v $(pwd)/certs/$DOMAIN/:/ssl/:ro \
  -v $(pwd)/nginx.conf:/etc/nginx/conf.d/nginx.conf:ro \
  nginx:latest
openssl s_client -connect localhost:8443 <<< "Q" 2>/dev/null | grep "=/"
docker stop nginx
```

Note that most services (including nginx used in the example) need to be told in some way to reload the certificate when it changes. This would normally be handled by acme.sh itself, but I don't want to give it root access or access to the Docker socket. Instead I'm relying on the reload file created by the `--reloadcmd` and handle this with a cronjob on the Docker host - every hour the cronjob checks if one of the certificate directories contains a reload file, issues commands via `docker exec` or restarts containers using the certificate and removes the reload file. This may seem a bit hacky, but I'd rather have another cronjob than giving out full system access to containers.

To keep an eye on this I am using a simple SSL expiration check that pings a healthcheck.io check if all configured URLs have a certificate that is valid for more than 30 days. If one of the certificates isn't valid or expires in less than 30 days, the ping check will trigger a notification on various channels.
