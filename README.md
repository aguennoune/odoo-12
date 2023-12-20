# Quick install

Installing Odoo 12 with one command.

(Supports multiple Odoo instances on one server)

Install [docker](https://docs.docker.com/get-docker/) and [docker-compose](https://docs.docker.com/compose/install/) yourself, then run:

``` bash
curl -s https://raw.githubusercontent.com/aguennoune/odoo-12/master/run.sh | sudo bash -s odoo-one 10012 20012
```

to set up first Odoo instance @ `localhost:10012` (default master password: `admin`)

and

``` bash
curl -s https://raw.githubusercontent.com/aguennoune/odoo-12/master/run.sh | sudo bash -s odoo-two 11012 21012
```

to set up another Odoo instance @ `localhost:11012` (default master password: `admin`)

Some arguments:
* First argument (**odoo-one**): Odoo deploy folder
* Second argument (**10012**): Odoo port
* Third argument (**20012**): live chat port

If `curl` is not found, install it:

``` bash
$ sudo apt-get install curl
# or
$ sudo yum install curl
```

# Usage

Start the container:
``` sh
docker-compose up
```

* Then open `localhost:10012` to access Odoo 12.0. If you want to start the server with a different port, change **10012** to another value in **docker-compose.yml**:

```
ports:
 - "10012:8069"
```

Run Odoo container in detached mode (be able to close terminal without stopping Odoo):

```
docker-compose up -d
```

**If you get the permission issue**, change the folder permission to make sure that the container is able to access the directory:

``` sh
$ git clone https://github.com/aguennoune/odoo-12/tree/master
$ sudo chmod -R 777 addons
$ sudo chmod -R 777 config
```

then, after running the container, we need to change the owner of the PostgreSQL data directory to the `odoo` user:

``` sh
$ sudo chown -R 999:999 config/postgresql.conf
$ sudo chown -R 999:999 config/pg_hba.conf
$ sudo chown -R 999:999 config/pg_ident.conf
$ sudo chown -R 999:999 pgdata_replica
$ sudo chown -R 999:999 archive
```


Increase maximum number of files watching from 8192 (default) to **524288**. In order to avoid error when we run multiple Odoo instances. This is an *optional step*. These commands are for Ubuntu user:

```
$ if grep -qF "fs.inotify.max_user_watches" /etc/sysctl.conf; then echo $(grep -F "fs.inotify.max_user_watches" /etc/sysctl.conf); else echo "fs.inotify.max_user_watches = 524288" | sudo tee -a /etc/sysctl.conf; fi
$ sudo sysctl -p    # apply new config immediately
```

# Custom addons

The **addons/** folder contains custom addons. Just put your custom addons if you have any.

# Odoo configuration & log

* To change Odoo configuration, edit file: **config/odoo.conf**.
* Log file: **config/odoo-server.log**
* Default database password (**admin_passwd**) is `minhng.info`, please change it @ [config/odoo.conf#L55](/config/odoo.conf#L55)

# Odoo container management

**Run Odoo**:

``` bash
docker-compose up -d
```

**Restart Odoo**:

``` bash
docker-compose restart
```

**Stop Odoo**:

``` bash
docker-compose down
```

# Live chat

In [docker-compose.yml#L21](docker-compose.yml#L21), we exposed port **20012** for live-chat on host.

Configuring **nginx** to activate live chat feature (in production):

``` conf
#...
server {
    #...
    location /longpolling/ {
        proxy_pass http://0.0.0.0:20012/longpolling/;
    }
    #...
}
#...
```

# docker-compose.yml

* odoo:12.0
* postgres:14.0

# Odoo 12 screenshots

![odoo-12-welcome-docker](screenshots/odoo-12-welcome-screenshot.png)

![odoo-12-apps-docker](screenshots/odoo-12-apps-screenshot.png)

![odoo-12-sales](screenshots/odoo-12-sales-screen.png)

###### How to replicate PostgreSQL database

So as to configure our first PostgreSQL database replication, we need to create a new user with replication privileges on the master server. This user will be used by the slave server to connect to the master server and replicate the database.

This will essentially give us a primary and a secondary server for better availability in case we lose our primary server. </br>

##### Get our Primary PostgreSQL Server Up and Running

Let's start by running our primary PostgreSQL in docker </br>
Few thing to note her: </br>
* We start our instance with a different name to identify it as the first instance with the `--name postgres-master` flag and `slave` for the second instance.

* Set unique data volumes for data between instances.

* Set unique config files for each instance - {! ./config/postgresql.conf !} - {! ./config/pg_hba.conf !} - {! ./config/pg_ident.conf !}

* Create and run our docker containers on the same network.

Let's create a new network so our instances can talk with each other:

``` bash
docker network create odoo-web
```

###### Start Master Instance on Master Server

``` bash
cd {PWD}/config

docker run -it --rm --name postgresql-master \
--net odoo-web \
-e POSTGRES_PASSWORD=odoo \
-e POSTGRES_USER=odoo_user \
-e POSTGRES_DB=db_dev \
-e PGDATA="/data" \
-v ${PWD}/pgdata:/data \
-v ${PWD}/config:/config \
-v ${PWD}/archive:/mnt/server/archive \
-p 5432:5432 \
postgres:14.0 -c 'config_file=/config/postgresql.conf'
```

###### Create Replication User on Master Server

``` bash
docker exec -it postgresql-master bash

# create a new user
createuser -U odoo_user -P -c 5 --replication replicationUser

exit
```

###### Enable Write-Ahead Log (WAL) Archiving on Master Server

{! ./config/postgresql.conf !}

Add the following lines to the end of the file:

```ini
wal_level = replica
max_wal_senders = 5

#  Enable Archive Mode
archive_mode = on

archive_command = 'test ! -f /mnt/server/archive/%f && cp %p /mnt/server/archive/%f'
```

###### Take a base backup:
To take a database backup, we'll be using the `pg_basebackup` utility. This utility is used to take a base backup of a running PostgreSQL database cluster. It is the standard tool for PostgreSQL replication and database backup and recovery.

``` bash
cd {PWD}/config

docker run -it --rm \
--net odoo-web \
-v ${PWD}/pgdata:/data \
--entrypoint /bin/bash \
postgres:14.0
```
Take the backup by logging into `postgres` with our `replicationUser` and writing the backup to `/data`:

``` bash
pg_basebackup -h postgresql-master -p 5432 -U replicationUser -D /data/ -Fp -Xs -R
```
Now we should see PostgreSQL data ready for our slave server in `${PWD}/pgdata`:

``` bash
ls -l pgdata
```

###### Start standby instance on Slave Server

``` bash
cd {PWD}/postgresql-slave

docker run -it --rm --name postgresql-slave \
--net odoo-web \
-e POSTGRES_PASSWORD=odoo \
-e POSTGRES_USER=odoo_user \
-e POSTGRES_DB=db_dev \
-e PGDATA="/data" \
-v ${PWD}/pgdata:/data \
-v ${PWD}/config:/config \
-v ${PWD}/archive:/mnt/server/archive \
-p 5433:5432 \
postgres:14.0 -c 'config_file=/config/postgresql.conf'
```

## Many thanks to:
`@minhng92` _ [Odoo version 12.0](https://github.com/minhng92/odoo-12-docker-compose)
`@marcel-dempers` _ [See PostgreSQL replication](https://github.com/marcel-dempers/docker-development-youtube-series)