# PCF Syslog Migration Release

This is a fork of [syslog-release](https://github.com/cloudfoundry/syslog-release) to transition tiles which currently provide their own log forwarding implementation into a world where syslog responsibilities are more centralized. Changes should always be made in the upstream syslog release with the only exception of migration-related changes which must have a specific end of life goal. All customizations must be configured via `syslog.migration.*` properties) and those defaults must be equivalent to the upstream defaults. Once a tile is no longer configuring `syslog.migration.*` properties, they should switch to the upstream syslog release. Available migration properties:

 * `syslog.migration.disabled` - If true, do not reconfigure rsyslog or forward /var/vcap/sys/log files (nearly equivalent to not installing the job).
 * `syslog.migration.insistent_custom_rule` - Rule will be applied even if the above property is `true`
 * `syslog.migration.message_format` - The message format used to send messages to remote endpoints. If no value is set, uses the upstream default.
     * `rfc5424` - structured data of `[instance@47450 director="%s" deployment="%s" group="%s" az="%s" id="%s"]`. This is the default setting.
     * `job_index` - structured data of `-`  and `[job=%s index=%d]` prefixed in the message
     * `job_index_id` - structured data of `-` and `[job=%s index=%d id=%s]` prefixed in the message

 * `syslog.migration.cleanup_conf_files` - List of filenames to remove from /etc/rsyslog.d/
---


# Syslog BOSH Release

This is a BOSH release to forward local syslog events in [RFC5424](https://tools.ietf.org/html/rfc5424) format to a remote syslog endpoint. It currently uses [rsyslog](http://www.rsyslog.com/) which is pre-installed by the stemcell.


## Usage

Download the latest release from [bosh.io](https://bosh.io/releases/github.com/cloudfoundry/syslog-release) and include it in your manifest:

```yml
releases:
- name: syslog
  version: latest
```


### Configure Forwarding

Add the [`syslog_forwarder`](https://bosh.io/jobs/syslog_forwarder?source=github.com/cloudfoundry/syslog-release) job to forward all local syslog messages from an instance to a syslog endpoint. Configure `address` and, optionally, `port` and `transport`:

```yml
instance_groups:
- name: some-instance-group
  jobs:
  - name: syslog_forwarder
    release: syslog
  properties:
    syslog:
      address: <IP or hostname>
```

By default, if the syslog endpoint is unavailable messages will be queued. Alternatively, configure `fallback_servers` for higher availability. Only TCP or RELP are supported for fallback functionality:

```yml
properties:
  syslog:
    address: 10.10.10.100
    fallback_servers:
    - address: 10.10.10.101
    - address: 10.10.10.102
```

TLS is supported with additional properties. The following example would forward syslog messages to [papertrailapp.com](https://papertrailapp.com/):

```yml
properties:
  syslog:
    address: logs4.papertrailapp.com
    port: 12345
    transport: tcp
    tls_enabled: true
    permitted_peer: "*.papertrailapp.com"
    ca_cert: |
      -----BEGIN CERTIFICATE-----
      MIIFdDCCBFygAwIBAgIQJ2buVutJ846r13Ci/ITeIjANBgkqhkiG9w0BAQwFADBv
      ...
      pu/xO28QOG8=
      -----END CERTIFICATE-----
      -----BEGIN CERTIFICATE-----
      MIIENjCCAx6gAwIBAgIBATANBgkqhkiG9w0BAQUFADBvMQswCQYDVQQGEwJTRTEU
      ...
      mnkPIAou1Z5jJh5VkpTYghdae9C8x49OhgQ=
      -----END CERTIFICATE-----
```

Note that you may need to include the *entire* certificate chain in `ca_cert` for the forwarding to work.

### Test Store

The [`syslog_storer`](https://bosh.io/jobs/syslog_storer?source=github.com/cloudfoundry/syslog-release) is meant for testing. Deploy it and configure your instances to forward logs to it. It should not be co-located with other jobs which also try to configure syslog. Received logs are stored in `/var/vcap/store/syslog_storer/syslog.log`.

```yml
instance_groups:
- name: syslog_storer
  jobs:
  - name: syslog_storer
    release: syslog
```

Remember to allow inbound traffic on TCP port 514 in your IaaS security groups.


## Format

This release forwards messages using the [RFC5424](https://tools.ietf.org/html/rfc5424) standard (natively supported by most log platforms). Forwarded messages are annotated with structured data (instance@[47450](https://www.iana.org/assignments/enterprise-numbers/enterprise-numbers)) that identify the originating BOSH instance (director, deployment, availability zone, instance group, and instance ID).

    <$PRI>$VERSION $TIMESTAMP $HOST $APP_NAME $PROC_ID $MSG_ID [instance@47450 director="$DIRECTOR" deployment="$DEPLOYMENT" group="$INSTANCE_GROUP" az="$AVAILABILITY_ZONE" id="$ID"] $MESSAGE

An example message from diego is transmitted as...

    <14>1 2017-01-25T13:25:03.18377Z 192.0.2.10 etcd - - [instance@47450 director="test-env" deployment="cf" group="diego_database" az="us-west1-a" id="83bd66e5-3fdf-44b7-bdd6-508deae7c786"] [INFO] the leader is [https://diego-database-0.etcd.service.cf.internal:4001]
    <14>1 2017-01-25T13:25:03.184491Z 192.0.2.10 bbs - - [instance@47450 director="test-env" deployment="cf" group="diego_database" az="us-west1-a" id="83bd66e5-3fdf-44b7-bdd6-508deae7c786"] {"timestamp":"1485350702.539694548","source":"bbs","message":"bbs.request.start-actual-lrp.starting","log_level":1,"data":{"actual_lrp_instance_key":{"instance_guid":"271f71c7-4119-4490-619f-4f44694717c0","cell_id":"diego_cell-2-41f21178-d619-4976-901c-325bc2d0d11d"},"actual_lrp_key":{"process_guid":"1545ce89-01e6-4b8f-9cb1-5654a3ecae10-137e7eb4-12de-457d-8e3e-1258e5a74687","index":5,"domain":"cf-apps"},"method":"POST","net_info":{"address":"192.0.2.12","ports":[{"container_port":8080,"host_port":61532},{"container_port":2222,"host_port":61533}]},"request":"/v1/actual_lrps/start","session":"418.1"}}

A sample logstash config with additional filters to extract instance metadata is in [`scripts/logstash-filters.conf`](scripts/logstash-filters.conf).


## Tech Notes

RSYSLOG is system for log processing; it is a drop-in replacement for the UNIX's venerable [syslog](https://en.wikipedia.org/wiki/Syslog), which logs messages to various files and/or log hosts. RSYSLOG can be configured as a **storer** (i.e. it receives log messages from other hosts) or a **forwarder** (i.e. it forwards system log messages to RSYSLOG storers, syslog servers, or log aggregation services).

The RSYSLOG configuration file is `/etc/rsyslog.conf`. The RSYSLOG forwarder's customizations are rendered into `/etc/rsyslog.d/rsyslog.conf`, which is included by the configuration file.
