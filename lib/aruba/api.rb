require 'tempfile'
require 'rbconfig'
require 'rspec'

RSpec::Matchers.define :be_successful_exit do
  match do |actual_exit_status|
    @actual_exit_status = actual_exit_status
    actual_exit_status == 0
  end

  failure_message_for_should do
    "expected zero (success) exit status but was #{@actual_exit_status}"
  end

  failure_message_for_should_not do
    "expected non-zero (failure) exit status but was #{@actual_exit_status}"
  end
end

module Aruba
module Api
  def in_current_dir(&block)
    _mkdir(current_dir)
    Dir.chdir(current_dir, &block)
  end

  def current_dir
    File.join(*dirs)
  end

  def cd(dir)
    dirs << dir
    raise "#{current_dir} is not a directory." unless File.directory?(current_dir)
  end

  def dirs
    @dirs ||= ['tmp/aruba']
  end

  def create_file(file_name, file_content)
    in_current_dir do
      _mkdir(File.dirname(file_name))
      File.open(file_name, 'w') { |f| f << file_content }
    end
  end

  def append_to_file(file_name, file_content)
    in_current_dir do
      File.open(file_name, 'a') { |f| f << file_content }
    end
  end

  def create_dir(dir_name)
    in_current_dir do
      _mkdir(dir_name)
    end
  end

  def check_file_presence(paths, expect_presence)
    in_current_dir do
      paths.each do |path|
        if expect_presence
          File.should be_file(path)
        else
          File.should_not be_file(path)
        end
      end
    end
  end

  def check_file_content(file, partial_content, expect_match)
    regexp = compile_and_escape(partial_content)
    in_current_dir do
      content = IO.read(file)
      if expect_match
        content.should =~ regexp
      else
        content.should_not =~ regexp
      end
    end
  end
  
  def check_directory_presence(paths, expect_presence)
    in_current_dir do
      paths.each do |path|
        if expect_presence
          File.should be_directory(path)
        else
          File.should_not be_directory(path)
        end
      end
    end
  end

  def _mkdir(dir_name)
    FileUtils.mkdir_p(dir_name) unless File.directory?(dir_name)
  end

  def unescape(string)
    eval(%{"#{string}"})
  end

  def compile_and_escape(string)
    Regexp.compile(Regexp.escape(string))
  end

  def combined_output
    @last_stdout + (@last_stderr == '' ? '' : "\n#{'-'*70}\n#{@last_stderr}")
  end

  def use_rvm(rvm_ruby_version)
    if File.exist?('config/aruba-rvm.yml')
      @rvm_ruby_version = YAML.load_file('config/aruba-rvm.yml')[rvm_ruby_version] || rvm_ruby_version
    else
      @rvm_ruby_version = rvm_ruby_version
    end
  end

  def use_rvm_gemset(rvm_gemset, empty_gemset)
    @rvm_gemset = rvm_gemset
    if empty_gemset && ENV['GOTGEMS'].nil?
      delete_rvm_gemset(rvm_gemset)
      create_rvm_gemset(rvm_gemset)
    end
  end
  
  def delete_rvm_gemset(rvm_gemset)
    raise "You haven't specified what ruby version rvm should use." if @rvm_ruby_version.nil?
    run "rvm --force gemset delete #{@rvm_ruby_version}@#{rvm_gemset}"
  end
  
  def create_rvm_gemset(rvm_gemset)
    raise "You haven't specified what ruby version rvm should use." if @rvm_ruby_version.nil?
    run "rvm --create #{@rvm_ruby_version}@#{rvm_gemset}"
  end

  def install_gems(gemfile)
    create_file("Gemfile", gemfile)
    if ENV['GOTGEMS'].nil?
      run("gem install bundler")
      run("bundle install")
    end
  end

  def run(cmd, fail_on_error=true)
    cmd = detect_ruby_script(cmd)
    cmd = detect_ruby(cmd)

    announce_or_puts("$ #{cmd}") if @announce_cmd

    stderr_file = Tempfile.new('cucumber')
    stderr_file.close
    in_current_dir do
      mode = RUBY_VERSION =~ /^1\.9/ ? {:external_encoding=>"UTF-8"} : 'r'
      IO.popen("#{cmd} 2> #{stderr_file.path}", mode) do |io|
        @last_stdout = io.read

        announce_or_puts(@last_stdout) if @announce_stdout
      end

      @last_exit_status = $?.exitstatus
    end
    @last_stderr = IO.read(stderr_file.path)

    announce_or_puts(@last_stderr) if @announce_stderr

    if(@last_exit_status != 0 && fail_on_error)
      fail("Exit status was #{@last_exit_status}. Output:\n#{combined_output}")
    end

    @last_stderr
  end

  def announce_or_puts(msg)
    if(@puts)
      puts(msg)
    else
      announce(msg)
    end
  end

  def detect_ruby(cmd)
    if cmd =~ /^ruby\s/
      cmd.gsub(/^ruby\s/, "#{current_ruby} ")
    else
      cmd
    end
  end

  COMMON_RUBY_SCRIPTS = /^(?:bundle|cucumber|gem|jeweler|rails|rake|rspec|spec)\s/

  def detect_ruby_script(cmd)
    if cmd =~ COMMON_RUBY_SCRIPTS
      "ruby -S #{cmd}"
    else
      cmd
    end
  end

  def current_ruby
    if @rvm_ruby_version
      rvm_ruby_version_with_gemset = @rvm_gemset ? "#{@rvm_ruby_version}@#{@rvm_gemset}" : @rvm_ruby_version
      "rvm #{rvm_ruby_version_with_gemset} ruby"
    else
      File.join(Config::CONFIG['bindir'], Config::CONFIG['ruby_install_name'])
    end
  end
end
end
