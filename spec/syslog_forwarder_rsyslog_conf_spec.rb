require 'helpers/bosh_template'

RSpec.describe 'syslog_forwarder rsyslog.conf' do
  let(:template_path) { 'jobs/syslog_forwarder/templates/rsyslog.conf.erb' }
  let(:job_name) { 'syslog_forwarder' }
  let(:minimum_manifest) do
    <<~MINIMUM_MANIFEST
    instance_groups:
    - name: syslog_forwarder
      jobs:
      - name: syslog_forwarder
    MINIMUM_MANIFEST
  end
  let(:links) do
    {
      "syslog_storer" => {
        "instances" => [
          { "address" => "my.syslog_storer.bosh" }
        ],
        "properties" => {
          "syslog" => {
            "port" => "some-syslog-storer-port",
            "transport" => "relp"
          }
        }
      }
    }
  end

  it 'defaults to rsyslog beinge configured with the RFC5424 format' do
    manifest = generate_manifest(minimum_manifest)
    actual_template = BoshTemplate.render(template_path, job_name, manifest, links)

    expected_message_format = Fixtures.read('rsyslog_with_rfc5424_format.conf')
    expect(actual_template).to include expected_message_format
  end

  it 'allows rsyslog to be configured with the RFC5424 format' do
    manifest = generate_manifest_with_message_format(minimum_manifest, 'rfc5424')
    actual_template = BoshTemplate.render(template_path, job_name, manifest, links)

    expected_message_format = Fixtures.read('rsyslog_with_rfc5424_format.conf')
    expect(actual_template).to include expected_message_format
  end

  it 'allows rsyslog to be configured with the job_index format' do
    manifest = generate_manifest_with_message_format(minimum_manifest, 'job_index')
    actual_template = BoshTemplate.render(template_path, job_name, manifest, links)

    expected_message_format = Fixtures.read('rsyslog_with_job_index_format.conf')
    expect(actual_template).to include expected_message_format
  end

  it 'allows rsyslog to be configured with the job_index_id format' do
    manifest = generate_manifest_with_message_format(minimum_manifest, 'job_index_id')
    actual_template = BoshTemplate.render(template_path, job_name, manifest, links)

    expected_message_format = Fixtures.read('rsyslog_with_job_index_id_format.conf')
    expect(actual_template).to include expected_message_format
  end

  it 'prevents rsyslog from being configured with unknown formats' do
    manifest = generate_manifest_with_message_format(minimum_manifest, 'crazy-format')
    expect {
      BoshTemplate.render(template_path, job_name, manifest, links)
    }.to raise_error(RuntimeError, "unknown syslog.migration.message_format: crazy-format")
  end

  it 'uses the default ca_cert path when ca_cert is not configured' do
    manifest = generate_manifest_tls(minimum_manifest)
    actual_template = BoshTemplate.render(template_path, job_name, manifest, links)
    default_ca_cert_config = "$DefaultNetstreamDriverCAFile /etc/ssl/certs/ca-certificates.crt"
    expect(actual_template).to include default_ca_cert_config
  end

  it 'uses the default ca_cert path when ca_cert is empty' do
    manifest = generate_manifest_tls(minimum_manifest, '')
    actual_template = BoshTemplate.render(template_path, job_name, manifest, links)
    default_ca_cert_config = "$DefaultNetstreamDriverCAFile /etc/ssl/certs/ca-certificates.crt"
    expect(actual_template).to include default_ca_cert_config
  end

  it 'uses the custom ca_cert path when ca_cert is configured' do
    manifest = generate_manifest_tls(minimum_manifest, '---ca_cert---')
    actual_template = BoshTemplate.render(template_path, job_name, manifest, links)
    default_ca_cert_config = "$DefaultNetstreamDriverCAFile /var/vcap/jobs/syslog_forwarder/config/ca_cert.pem"
    expect(actual_template).to include default_ca_cert_config
  end
end

def generate_manifest(raw_manifest)
  manifest = YAML.load(raw_manifest)
  yield(manifest) if block_given?
  manifest
end

def generate_manifest_with_message_format(raw_manifest, message_format)
  generate_manifest(raw_manifest) do |manifest|
    set_syslog_properties(manifest, {
      'syslog' => {
        'migration' => {
          'message_format' => message_format
        }
      }
    })
  end
end

def generate_manifest_tls(raw_manifest, custom_ca_cert=nil)
  generate_manifest(raw_manifest) do |manifest|
    properties = {
      'syslog' => {
        'tls_enabled' => true
      }
    }
    unless custom_ca_cert.nil?
      properties['syslog']['ca_cert'] = custom_ca_cert
    end

    set_syslog_properties(manifest, properties)
  end
end

def set_syslog_properties(manifest, properties)
  manifest['instance_groups'][0]['jobs'][0]['properties'] = properties
end
