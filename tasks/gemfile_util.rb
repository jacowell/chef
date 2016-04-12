require "bundler"
require "set"

module GemfileUtil
  # gemspec and gem need to use absolute paths for things in order for our Gemfile
  # to be *included* in another. This works around some issues in bundler 1.11.2.
  def gemspec(options = {})
    options[:path] = File.expand_path(options[:path] || ".", Bundler.default_gemfile.dirname)
    super
  end

  #
  # gemspec and gem need to use absolute paths for things in order for our Gemfile
  # to be *included* in another. This works around some issues in bundler 1.11.2.
  # Also adds `override: true`, which allows your statement to override any other
  # gem statement about the same gem in the Gemfile.
  #
  def gem(name, *args)
    current_dep = dependencies.find { |dep| dep.name == name }

    # Set path to absolute in case this is an included Gemfile in bundler 1.11.2 and below
    options = args[-1].is_a?(Hash) ? args[-1] : {}
    if options[:path]
      options[:path] = File.expand_path(options[:path], Bundler.default_gemfile.dirname)
    end
    # Handle override
    if options[:override]
      options.delete(:override)
      if current_dep
        dependencies.delete(current_dep)
      end
    else
      # If an override gem already exists, and we're not an override gem,
      # ignore this gem in favor of the override (but warn if they don't match)
      if overridden_gems.include?(name)
        args.pop if args[-1].is_a?(Hash)
        version = args || [">=0"]
        desired_dep = Bundler::Dependency.new(name, version, options.dup)
        unless current_dep =~ desired_dep
          puts "WARNING: replaced Gemfile dependency #{desired_dep} with override gem #{current_dep}"
        end
        return
      end
    end

    # Add the gem normally
    super

    overridden_gems << name if options[:override]

    # Emit a warning if we're replacing a dep that doesn't match
    if current_dep
      added_dep = dependencies.find { |dep| dep.name == name }
      unless current_dep =~ added_dep
        puts "WARNING: replaced Gemfile dependency #{current_dep} with #{added_dep}"
      end
    end
  end

  def overridden_gems
    @overridden_gems ||= Hash.new
  end

  #
  # Include
  #
  def include_locked_gemfile(gemfile)
    puts "Loading locks from #{gemfile} ..."
    gemfile = File.expand_path(gemfile, Bundler.default_gemfile.dirname)

    #
    # Read the gemfile and inject its locks as first-class dependencies
    #
    old_gemfile = ENV["BUNDLE_GEMFILE"]
    old_frozen = Bundler.settings[:frozen]
    begin
      # Set frozen to true so we don't try to install stuff.
      Bundler.settings[:frozen] = true
      # Set BUNDLE_GEMFILE to the new gemfile temporarily so all bundler's things work
      # This works around some issues in bundler 1.11.2.
      ENV["BUNDLE_GEMFILE"] = gemfile
      bundle = Bundler::Definition.build(gemfile, "#{gemfile}.lock", nil)

      # Go through and create the actual gemfile from the given locks and
      # groups.
      bundle.resolve.sort_by { |spec| spec.name }.each do |spec|
        # bundler can't be installed by bundler so don't pin it.
        next if spec.name == "bundler"

        # Copy groups and platforms from included Gemfile
        gem_metadata = {}
        dep = bundle.dependencies.find { |d| d.name == spec.name }
        if dep
          gem_metadata[:groups] = dep.groups unless dep.groups == [:default]
          gem_metadata[:platforms] = dep.platforms unless dep.platforms.empty?
        end
        gem_metadata[:override] = true

        # Copy source information from included Gemfile
        use_version = false
        case spec.source
        when Bundler::Source::Rubygems
          gem_metadata[:source] = spec.source.remotes.first.to_s
          use_version = true
        when Bundler::Source::Git
          gem_metadata[:git] = spec.source.uri.to_s
          gem_metadata[:ref] = spec.source.revision
        when Bundler::Source::Path
          gem_metadata[:path] = spec.source.path.to_s
        else
          raise "Unknown source #{spec.source} for gem #{spec.name}"
        end

        # Emit the dep
        if use_version
          gem spec.name, spec.version, gem_metadata
        else
          gem spec.name, gem_metadata
        end
      end

      puts "Loaded #{bundle.resolve.count} locked gem versions from #{gemfile}"
    rescue Exception
      # Bundler does a bad job of rescuing.
      puts $!
      puts $!.backtrace
      raise
    ensure
      Bundler.settings[:frozen] = old_frozen
      ENV["BUNDLE_GEMFILE"] = old_gemfile
    end
    puts "done"
  end
end
