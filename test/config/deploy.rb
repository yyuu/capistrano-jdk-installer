set :application, "capistrano-jdk-installer"
set :repository,  "."
set :deploy_to do
  File.join("/home", user, application)
end
set :deploy_via, :copy
set :scm, :none
set :use_sudo, false
set :user, "vagrant"
set :password, "vagrant"
set :ssh_options, {:user_known_hosts_file => "/dev/null"}

## java ##
set(:java_oracle_username) { ENV["JAVA_ORACLE_USERNAME"] || abort("java_oracle_username was not set") }
set(:java_oracle_password) { ENV["JAVA_ORACLE_PASSWORD"] || abort("java_oracle_password was not set") }

role :web, "192.168.33.10"
role :app, "192.168.33.10"
role :db,  "192.168.33.10", :primary => true

$LOAD_PATH.push(File.expand_path("../../lib", File.dirname(__FILE__)))
require "capistrano-jdk-installer"

def _invoke_command(cmdline, options={})
  via = options.delete(:via)
  if via == :run_locally
    run_locally(cmdline)
  else
    invoke_command(cmdline, options)
  end
end

def assert_file_exists(file, options={})
  begin
    _invoke_command("test -f #{file.dump}", options)
  rescue
    logger.debug("assert_file_exists(#{file}) failed.")
    _invoke_command("ls #{File.dirname(file).dump}", options)
    raise
  end
end

def assert_file_not_exists(file, options={})
  begin
    _invoke_command("test \! -f #{file.dump}", options)
  rescue
    logger.debug("assert_file_not_exists(#{file}) failed.")
    _invoke_command("ls #{File.dirname(file).dump}", options)
    raise
  end
end

def assert_command(cmdline, options={})
  begin
    _invoke_command(cmdline, options)
  rescue
    logger.debug("assert_command(#{cmdline}) failed.")
    raise
  end
end

def assert_command_fails(cmdline, options={})
  failed = false
  begin
    _invoke_command(cmdline, options)
  rescue
    logger.debug("assert_command_fails(#{cmdline}) failed.")
    failed = true
  ensure
    abort unless failed
  end
end

def reset_java!
  variables.each_key do |key|
    reset!(key) if /^java_/ =~ key
  end
end

def uninstall_java!
  run("rm -rf #{java_home.dump}")
  run("rm -f #{java_archive_file.dump}")
  run_locally("rm -rf #{java_home_local.dump}")
end

task(:test_all) {
  find_and_execute_task("test_default")
  find_and_execute_task("test_with_java5")
  find_and_execute_task("test_with_java6")
  find_and_execute_task("test_with_remote")
  find_and_execute_task("test_with_local")
}

namespace(:test_default) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_default", "test_default:setup"
  after "test_default", "test_default:teardown"

  task(:setup) {
    reset_java!
    set(:java_version_name, "7u15")
    set(:java_accept_license, true)
    set(:java_license_title, "Oracle Binary Code License Agreement for Java SE")
    set(:java_setup_remotely, true)
    set(:java_setup_locally, true)
    set(:java_tools_path_local) { File.expand_path("tmp/java") }
    set(:java_installer_json_expires, 300)
    set(:java_installer_json_keep_stale, false)
    uninstall_java!
    find_and_execute_task("deploy:setup")
  }

  task(:teardown) {
    uninstall_java!
  }

  task(:test_run_java) {
    assert_file_exists(java_bin)
    assert_command("#{java_cmd} -version")
  }

  task(:test_run_java_via_run_locally) {
    assert_file_exists(java_bin_local, :via => :run_locally)
    assert_command("#{java_cmd_local} -version", :via => :run_locally)
  }
}

namespace(:test_with_java5) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_java5", "test_with_java5:setup"
  after "test_with_java5", "test_with_java5:teardown"

  task(:setup) {
    reset_java!
    set(:java_version_name, "1_5_0_22")
    set(:java_accept_license, true)
    set(:java_license_title, "Oracle Binary Code License Agreement for Java SE")
    set(:java_setup_remotely, true)
    set(:java_setup_locally, true)
    set(:java_tools_path_local) { File.expand_path("tmp/java") }
    set(:java_installer_json_expires, 300)
    set(:java_installer_json_keep_stale, false)
    uninstall_java!
    find_and_execute_task("deploy:setup")
  }

  task(:teardown) {
    uninstall_java!
  }

  task(:test_run_java) {
    assert_file_exists(java_bin)
    assert_command("#{java_cmd} -version")
  }

  task(:test_run_java_via_run_locally) {
    assert_file_exists(java_bin_local, :via => :run_locally)
    assert_command("#{java_cmd_local} -version", :via => :run_locally)
  }
}

namespace(:test_with_java6) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_java6", "test_with_java6:setup"
  after "test_with_java6", "test_with_java6:teardown"

  task(:setup) {
    reset_java!
    set(:java_version_name, "6u39")
    set(:java_accept_license, true)
    set(:java_license_title, "Oracle Binary Code License Agreement for Java SE")
    set(:java_setup_remotely, true)
    set(:java_setup_locally, true)
    set(:java_tools_path_local) { File.expand_path("tmp/java") }
    set(:java_installer_json_expires, 300)
    set(:java_installer_json_keep_stale, false)
    uninstall_java!
    find_and_execute_task("deploy:setup")
  }

  task(:teardown) {
    uninstall_java!
  }

  task(:test_run_java) {
    assert_file_exists(java_bin)
    assert_command("#{java_cmd} -version")
  }

  task(:test_run_java_via_run_locally) {
    assert_file_exists(java_bin_local, :via => :run_locally)
    assert_command("#{java_cmd_local} -version", :via => :run_locally)
  }
}

namespace(:test_with_remote) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_remote", "test_with_remote:setup"
  after "test_with_remote", "test_with_remote:teardown"

  task(:setup) {
    reset_java!
    set(:java_version_name, "7u15")
    set(:java_accept_license, true)
    set(:java_license_title, "Oracle Binary Code License Agreement for Java SE")
    set(:java_setup_remotely, true)
    set(:java_setup_locally, false)
    set(:java_tools_path_local) { File.expand_path("tmp/java") }
    set(:java_installer_json_expires, 300)
    set(:java_installer_json_keep_stale, false)
    uninstall_java!
    find_and_execute_task("deploy:setup")
  }

  task(:teardown) {
    uninstall_java!
  }

  task(:test_run_java) {
    assert_file_exists(java_bin)
    assert_command("#{java_cmd} -version")
  }

  task(:test_run_java_via_run_locally) {
    assert_file_not_exists(java_bin_local, :via => :run_locally)
    assert_command_fails("#{java_cmd_local} -version", :via => :run_locally)
  }
}

namespace(:test_with_local) {
  task(:default) {
    methods.grep(/^test_/).each do |m|
      send(m)
    end
  }
  before "test_with_local", "test_with_local:setup"
  after "test_with_local", "test_with_local:teardown"

  task(:setup) {
    reset_java!
    set(:java_version_name, "7u15")
    set(:java_accept_license, true)
    set(:java_license_title, "Oracle Binary Code License Agreement for Java SE")
    set(:java_setup_remotely, false)
    set(:java_setup_locally, true)
    set(:java_tools_path_local) { File.expand_path("tmp/java") }
    set(:java_installer_json_expires, 300)
    set(:java_installer_json_keep_stale, false)
    uninstall_java!
    find_and_execute_task("deploy:setup")
  }

  task(:teardown) {
    uninstall_java!
  }

  task(:test_run_java) {
    assert_file_not_exists(java_bin)
    assert_command_fails("#{java_cmd} -version")
  }

  task(:test_run_java_via_run_locally) {
    assert_file_exists(java_bin_local, :via => :run_locally)
    assert_command("#{java_cmd_local} -version", :via => :run_locally)
  }
}

# vim:set ft=ruby sw=2 ts=2 :
