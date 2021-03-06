require 'bosh_ladle/bosh_lite'
require 'bosh_ladle/cli'

module BOSHLadle
  describe Cli do
    subject(:cli) { Cli.new }
    let(:key_id) { 'qux' }
    let(:key_secret) { 'barz' }
    let(:fake_ec2) { double('ec2') }

    def capture_stdio
      stderr_io = $stderr
      stdout_io = $stdout

      $stderr = StringIO.new
      $stdout = StringIO.new

      yield

      $stderr.rewind
      $stdout.rewind

      stuff_printed_to_stderr_during_yield = $stderr.read
      stuff_printed_to_stdout_during_yield = $stdout.read

      $stderr = stderr_io
      $stdout = stdout_io

      return stuff_printed_to_stderr_during_yield, stuff_printed_to_stdout_during_yield
    end

    describe '#run' do
      around do |spec|
        ENV['AWS_ACCESS_KEY_ID'] = key_id
        ENV['AWS_SECRET_ACCESS_KEY'] = key_secret
        spec.run
        ENV.delete('AWS_ACCESS_KEY_ID')
        ENV.delete('AWS_SECRET_ACCESS_KEY')
      end

      before do
        allow(AWS::EC2).to receive(:new).with(access_key_id: key_id, secret_access_key: key_secret).and_return fake_ec2
        allow(BOSHLite).to receive(:spinup)
      end

      it 'parses command line options' do
        cli.run(%w(-i i -s s -g g -k k -n n -d 78))

        expect(cli.opts).to eq({help: false,
                                instance_type: 'i',
                                instance_type_given: true,
                                key_pair: 'k',
                                key_pair_given: true,
                                name: 'n',
                                name_given: true,
                                security_group: 'g',
                                security_group_given: true,
                                subnet_id: 's',
                                subnet_id_given: true,
                                disk_size: 78,
                                disk_size_given: true})
      end

      it 'raises if you do not provide required options' do
        capture_stdio do
          expect { cli.run([]) }.to raise_error(SystemExit)
        end
      end

      it 'raises if you provide invalid options' do
        stderr, _ = capture_stdio do
          expect { cli.run(%w(-a abc -x efg)) }.to raise_error(SystemExit)
        end

        expect(stderr).to include('unknown argument')
      end

      it 'uses defaults if you leave out optional parameters' do
        cli.run(%w(-s s -n n))

        expect(cli.opts).to eq({help: false,
                                instance_type: 'm3.xlarge',
                                key_pair: 'gocd_bosh_lite',
                                name: 'n',
                                name_given: true,
                                security_group: 'bosh',
                                subnet_id: 's',
                                subnet_id_given: true,
                                disk_size: 40})
      end

      it 'raises ArgumentError if AWS credentials are not in env' do
        ENV.delete('AWS_ACCESS_KEY_ID')
        expect { cli.run(%w(-s s -n n)) }.to raise_error(ArgumentError, 'Please set AWS_ACCESS_KEY_ID in the environment')
        ENV['AWS_ACCESS_KEY_ID'] = key_id

        ENV.delete('AWS_SECRET_ACCESS_KEY')
        expect { cli.run(%w(-s s -n n)) }.to raise_error(ArgumentError, 'Please set AWS_SECRET_ACCESS_KEY in the environment')
      end

      it 'shows usage information' do
        ENV.delete('AWS_SECRET_ACCESS_KEY')
        expect { capture_stdio { cli.run(%w(-h)) } }.to raise_exception SystemExit
      end

      it 'returns a status code' do
        expect(cli.run(%w|-s s -n n|)).to eq 0
      end

      it 'spins up a BOSH lite VM' do
        subnet = 'subnet-deadbeef'
        name = 'myBOSHLite'
        security_group = 'where-am-i'
        key_pair = 'ham-and-pears'
        instance_type = 'miniscule'
        disk_size = '77'

        expect(BOSHLite).to receive(:spinup).with(fake_ec2, subnet, name, security_group, key_pair, instance_type,
                                                  disk_size.to_i)

        cli.run ['-s', subnet, '-n', name, '-g', security_group, '-k', key_pair, '-i', instance_type, '-d', disk_size]
      end
    end
  end
end
