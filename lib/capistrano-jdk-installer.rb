require "capistrano-jdk-installer/jdk-installer"
require "capistrano-jdk-installer/version"
require "capistrano/configuration/actions/file_transfer_ext"

module Capistrano
  module JDKInstaller
    def self.extended(configuration)
      configuration.load {
        namespace(:java) {
          ## JDK installer
          _cset(:java_installer) { JDKInstaller.new(java_installer_options) }
          _cset(:java_installer_options) {{
            :logger => logger, :keep_stale => java_installer_json_keep_stale,
            :file => java_installer_json_cache, :ttl => java_installer_json_expires, :uri => java_installer_json_uri,
            :username => java_oracle_username, :password => java_oracle_password,
          }}
          _cset(:java_installer_json_uri, "http://updates.jenkins-ci.org/updates/hudson.tools.JDKInstaller.json")
          _cset(:java_installer_json_cache) { File.join(java_archive_path_local, "hudson.tools.JDKInstaller.json") }
          _cset(:java_installer_json_expires, 259200) # 3 days
          _cset(:java_installer_json_keep_stale, true) # keep staled cache even if get fails
          _cset(:java_installer_tool) { java_installer[java_version_regex] }
          _cset(:java_installer_tool_local) { java_installer[java_version_regex_local] }

          ## JDK version settings
          _cset(:java_version_name) { abort("You must specify JDK version explicitly.") }
          _cset(:java_platform) { JDKInstaller.platform_string(java_version_name, capture("uname -s"), capture("uname -m")) }
          _cset(:java_platform_local) { JDKInstaller.platform_string(java_version_name, run_locally("uname -s"), run_locally("uname -m")) }
          _cset(:java_version_regex) {
            Regexp.new(Regexp.escape("#{java_version_name}-#{java_platform}"), Regexp::IGNORECASE)
          }
          _cset(:java_version_regex_local) {
            Regexp.new(Regexp.escape("#{java_version_name}-#{java_platform_local}"), Regexp::IGNORECASE)
          }

          ## JDK paths
          _cset(:java_tools_path) { File.join(shared_path, "tools", "java") }
          _cset(:java_tools_path_local) { File.expand_path("tools/java") }
          _cset(:java_archive_path) { java_tools_path }
          _cset(:java_archive_path_local) { java_tools_path_local }
          _cset(:java_home) { java_installer_tool.install_path(:path => java_tools_path) }
          _cset(:java_home_local) { java_installer_tool_local.install_path(:path => java_tools_path_local) }
          _cset(:java_bin) { File.join(java_home, "bin", "java") }
          _cset(:java_bin_local) { File.join(java_home_local, "bin", "java") }
          _cset(:java_cmd) { "env JAVA_HOME=#{java_home.dump} #{java_bin.dump}" }
          _cset(:java_cmd_local) { "env JAVA_HOME=#{java_home_local.dump} #{java_bin_local.dump}" }
          _cset(:java_archive_file) { File.join(java_archive_path, java_installer_tool.basename) }
          _cset(:java_archive_file_local) { File.join(java_archive_path_local, java_installer_tool_local.basename) }

          ## license settings
          _cset(:java_accept_license, false)
          _cset(:java_license_title, nil)
          _cset(:java_oracle_username) { abort("java_oracle_username was not set") }
          _cset(:java_oracle_password) { abort("java_oracle_password was not set") }

          def _invoke_command(cmdline, options={})
            if options[:via] == :run_locally
              run_locally(cmdline)
            else
              invoke_command(cmdline, options)
            end
          end

          def _download(jdk, filename, options={})
            if FileTest.exist?(filename)
              logger.info("Found downloaded archive: #{filename}")
            else
              if jdk.license_title != java_license_title or !java_accept_license
                abort("You must accept JDK license before downloading.")
              end
              jdk.download(filename, fetch(:java_download_options, {}).merge(options))
            end
          end

          def _upload(filename, remote_filename, options={})
            _invoke_command("mkdir -p #{File.dirname(remote_filename).dump}", options)
            transfer_if_modified(:up, filename, remote_filename, fetch(:java_upload_options, {}).merge(options))
          end

          def _install(jdk, filename, destination, options={})
            cmdline = jdk.install_command(filename, destination, fetch(:java_install_options, {}).merge(options))
            _invoke_command(cmdline, options)
          end

          def _installed?(destination, options={})
            java = File.join(destination, "bin", "java")
            cmdline = "test -d #{destination.dump} && test -x #{java.dump}"
            _invoke_command(cmdline, options)
            true
          rescue
            false
          end

          ## tasks
          desc("Install java.")
          task(:setup, :roles => :app, :except => { :no_release => true }) {
            setup_remotely if fetch(:java_setup_remotely, true)
            setup_locally if fetch(:java_setup_locally, false)
          }
          after "deploy:setup", "java:setup"

          desc("Install java locally.")
          task(:setup_locally, :except => { :no_release => true }) {
            _download(java_installer_tool_local, java_archive_file_local, :via => :run_locally)
            unless _installed?(java_home_local, :via => :run_locally)
              _install(java_installer_tool_local, java_archive_file_local, java_home_local, :via => :run_locally)
              _installed?(java_home_local, :via => :run_locally)
            end
          }

          task(:setup_remotely, :except => { :no_release => true }) {
            filename = File.join(java_archive_path_local, File.basename(java_archive_file))
            _download(java_installer_tool, filename)
            _upload(filename, java_archive_file)
            unless _installed?(java_home)
              _install(java_installer_tool, java_archive_file, java_home)
              _installed?(java_home)
            end
          }
        }
      }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::JDKInstaller)
end

# vim:set ft=ruby sw=2 ts=2 :
