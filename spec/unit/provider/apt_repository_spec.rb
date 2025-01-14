#
# Author:: Thom May (<thom@chef.io>)
# Copyright:: Copyright (c) 2016 Chef Software, Inc.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "spec_helper"

APT_KEY_FINGER = <<-EOF
/etc/apt/trusted.gpg
--------------------
pub   1024D/437D05B5 2004-09-12
      Key fingerprint = 6302 39CC 130E 1A7F D81A  27B1 4097 6EAF 437D 05B5
uid                  Ubuntu Archive Automatic Signing Key <ftpmaster@ubuntu.com>
sub   2048g/79164387 2004-09-12

pub   1024D/FBB75451 2004-12-30
      Key fingerprint = C598 6B4F 1257 FFA8 6632  CBA7 4618 1433 FBB7 5451
uid                  Ubuntu CD Image Automatic Signing Key <cdimage@ubuntu.com>

pub   4096R/C0B21F32 2012-05-11
      Key fingerprint = 790B C727 7767 219C 42C8  6F93 3B4F E6AC C0B2 1F32
uid                  Ubuntu Archive Automatic Signing Key (2012) <ftpmaster@ubuntu.com>

pub   4096R/EFE21092 2012-05-11
      Key fingerprint = 8439 38DF 228D 22F7 B374  2BC0 D94A A3F0 EFE2 1092
uid                  Ubuntu CD Image Automatic Signing Key (2012) <cdimage@ubuntu.com>

EOF

GPG_FINGER = <<-EOF
pub  1024D/02A818DD 2009-04-22 Cloudera Apt Repository
      Key fingerprint = F36A 89E3 3CC1 BD0F 7107  9007 3275 74EE 02A8 18DD
sub  2048g/D1CA74A1 2009-04-22
EOF

describe Chef::Provider::AptRepository do
  let(:new_resource) { Chef::Resource::AptRepository.new("multiverse") }

  let(:shellout_env) { { env: { "LANG" => "en_US", "LANGUAGE" => "en_US" } } }
  let(:provider) do
    node = Chef::Node.new
    events = Chef::EventDispatch::Dispatcher.new
    run_context = Chef::RunContext.new(node, {}, events)
    Chef::Provider::AptRepository.new(new_resource, run_context)
  end

  let(:apt_key_finger) do
    r = double("Mixlib::ShellOut", stdout: APT_KEY_FINGER, exitstatus: 0, live_stream: true)
    allow(r).to receive(:run_command)
    r
  end

  let(:gpg_finger) do
    r = double("Mixlib::ShellOut", stdout: GPG_FINGER, exitstatus: 0, live_stream: true)
    allow(r).to receive(:run_command)
    r
  end

  let(:apt_fingerprints) do
    %w{630239CC130E1A7FD81A27B140976EAF437D05B5
C5986B4F1257FFA86632CBA746181433FBB75451
790BC7277767219C42C86F933B4FE6ACC0B21F32
843938DF228D22F7B3742BC0D94AA3F0EFE21092}
  end

  it "responds to load_current_resource" do
    expect(provider).to respond_to(:load_current_resource)
  end

  describe "#is_key_id?" do
    it "should detect a key" do
      expect(provider.is_key_id?("A4FF2279")).to be_truthy
    end
    it "should detect a key with a hex signifier" do
      expect(provider.is_key_id?("0xA4FF2279")).to be_truthy
    end
    it "should reject a key with the wrong length" do
      expect(provider.is_key_id?("4FF2279")).to be_falsey
    end
    it "should reject a key with non-hex characters" do
      expect(provider.is_key_id?("A4KF2279")).to be_falsey
    end
  end

  describe "#extract_fingerprints_from_cmd" do
    before do
      expect(Mixlib::ShellOut).to receive(:new).and_return(apt_key_finger)
    end

    it "should run the desired command" do
      expect(apt_key_finger).to receive(:run_command)
      provider.extract_fingerprints_from_cmd("apt-key finger")
    end

    it "should return a list of key fingerprints" do
      expect(provider.extract_fingerprints_from_cmd("apt-key finger")).to eql(apt_fingerprints)
    end
  end

  describe "#no_new_keys?" do
    before do
      allow(provider).to receive(:extract_fingerprints_from_cmd).with("apt-key finger").and_return(apt_fingerprints)
    end

    let(:file) { "/tmp/remote-gpg-keyfile" }

    it "should match a set of keys" do
      allow(provider).to receive(:extract_fingerprints_from_cmd).with("gpg --with-fingerprint #{file}").and_return(Array(apt_fingerprints.first))
      expect(provider.no_new_keys?(file)).to be_truthy
    end

    it "should notice missing keys" do
      allow(provider).to receive(:extract_fingerprints_from_cmd).with("gpg --with-fingerprint #{file}").and_return(%w{ F36A89E33CC1BD0F71079007327574EE02A818DD })
      expect(provider.no_new_keys?(file)).to be_falsey
    end
  end

  describe "#install_ppa_key" do
    let(:url) { "https://launchpad.net/api/1.0/~chef/+archive/main" }
    let(:key) { "C5986B4F1257FFA86632CBA746181433FBB75451" }

    it "should get a key" do
      simples = double("HTTP")
      allow(simples).to receive(:get).and_return("\"#{key}\"")
      expect(Chef::HTTP::Simple).to receive(:new).with(url).and_return(simples)
      expect(provider).to receive(:install_key_from_keyserver).with(key, "keyserver.ubuntu.com")
      provider.install_ppa_key("chef", "main")
    end
  end

  describe "#make_ppa_url" do
    it "should ignore non-ppa repositories" do
      expect(provider.make_ppa_url("some_string")).to be_nil
    end

    it "should create a URL" do
      expect(provider).to receive(:install_ppa_key).with("chef", "main").and_return(true)
      expect(provider.make_ppa_url("ppa:chef/main")).to eql("http://ppa.launchpad.net/chef/main/ubuntu")
    end
  end

  describe "#build_repo" do
    it "should create a repository string" do
      target = %Q{deb      "http://test/uri" unstable main\n}
      expect(provider.build_repo("http://test/uri", "unstable", "main", false, nil)).to eql(target)
    end

    it "should create a repository string with source" do
      target = %Q{deb      "http://test/uri" unstable main\ndeb-src  "http://test/uri" unstable main\n}
      expect(provider.build_repo("http://test/uri", "unstable", "main", false, nil, true)).to eql(target)
    end

    it "should create a repository string with options" do
      target = %Q{deb      [trusted=yes] "http://test/uri" unstable main\n}
      expect(provider.build_repo("http://test/uri", "unstable", "main", true, nil)).to eql(target)
    end

    it "should handle a ppa repo" do
      target = %Q{deb      "http://ppa.launchpad.net/chef/main/ubuntu" unstable main\n}
      expect(provider).to receive(:make_ppa_url).with("ppa:chef/main").and_return("http://ppa.launchpad.net/chef/main/ubuntu")
      expect(provider.build_repo("ppa:chef/main", "unstable", "main", false, nil)).to eql(target)
    end
  end

end
