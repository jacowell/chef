# This buys us the ability to be included in other Gemfiles
require_relative "tasks/gemfile_util"
extend GemfileUtil

source "https://rubygems.org"
gemspec name: "chef"

gem "activesupport", "< 4.0.0", group: :compat_testing, platform: "ruby"
gem "chef-config", path: File.expand_path("../chef-config", __FILE__) if File.exist?(File.expand_path("../chef-config", __FILE__))
# Ensure that we can always install rake, regardless of gem groups
gem "rake"

# Go back to released version once the next version is released with working Gemfile
# Until a version of chef-zero is released with a valid Gemfile.
gem "chef-zero", github: "chef/chef-zero", ref: "c67095f4da311feb3d63cfd35cb25ee07e49f4b2"

group(:omnibus_package) do
  gem "appbundler"
  gem "rb-readline"
  gem "nokogiri"
end
group(:omnibus_package, :test) do
  # Remove "master" bit when cheffish tests succeed in Ruby 2.2
  gem "cheffish", github: "chef/cheffish"
end
group(:omnibus_package, :pry) do
  gem "pry"
  gem "pry-byebug"
  gem "pry-remote"
  gem "pry-stack_explorer"
end
# These are used for external tests
group(:test) do
  gem "chef-provisioning"
  gem "chef-provisioning-aws"
  gem "chef-rewind"
  gem "chef-sugar"
  gem "chefspec"
  gem "halite"
  gem "poise"
  gem "knife-windows"
  gem "foodcritic"
end

group(:docgen) do
  gem "yard"
end

group(:maintenance) do
  gem "tomlrb"

  # To sync maintainers with github
  gem "octokit"
  gem "netrc"
end

# Everything except AIX
group(:linux, :bsd, :mac_os_x, :solaris, :windows, :ruby_prof) do
  # may need to disable this in insolation on fussy builds like AIX, RHEL4, etc
  gem "ruby-prof"
end
# Everything except AIX and Windows
group(:linux, :bsd, :mac_os_x, :solaris) do
  gem "ruby-shadow"
end

group(:development, :test) do
  gem "simplecov"
  gem "rack"

  # for testing new chefstyle rules
  # gem 'chefstyle', github: 'chef/chefstyle'
  gem "chefstyle", git: "https://github.com/chef/chefstyle.git", branch: "master"
end

group(:changelog) do
  gem "github_changelog_generator", "1.11.3"
end

group(:travis) do
  # See `bundler-audit` in .travis.yml
  gem "bundler-audit", git: "https://github.com/rubysec/bundler-audit.git", ref: "4e32fca"
end

instance_eval(ENV["GEMFILE_MOD"]) if ENV["GEMFILE_MOD"]

# If you want to load debugging tools into the bundle exec sandbox,
# add these additional dependencies into chef/Gemfile.local
eval(IO.read(__FILE__ + ".local"), binding) if File.exist?(__FILE__ + ".local")
