require "capistrano-jdk-installer/version"
require 'capistrano/transfer'
require 'json'
require 'logger'
require 'mechanize'
require 'net/sftp'
require 'uri'

module Capistrano
  module JDKInstaller
    def download_archive(uri, archive)
      if FileTest.exist?(archive)
        logger.info("Found downloaded archive: #{archive}")
      else
        if java_release_license_title != java_license_title or !java_accept_license
          abort("You must accept JDK license before downloading.")
        end

        logger.info("Download archive from #{uri}.")
        unless dry_run
          run_locally("mkdir -p #{File.dirname(archive)}")
          page = java_mechanize_agent.get(uri)
          1.upto(16) { # to avoid infinity loop...
            if page.uri.host == "login.oracle.com" # login.oracle.com doesn't return proper Content-Type
              page = Mechanize::Page.new(page.uri, page.response, page.body, page.code, java_mechanize_agent) if page.is_a?(Mechanize::File)
              form = page.form_with
              form["ssousername"] = java_oracle_username
              form["password"] = java_oracle_password
              page = java_mechanize_agent.submit(form)
            else
              page.save(archive)
              logger.info("Wrote #{page.body.size} bytes to #{archive}.")
              break
            end
          }
        end
      end
    end

    def upload_archive(from, to, options={}, &block)
      mode = options.delete(:mode)
      execute_on_servers(options) { |servers|
        targets = servers.map { |server| sessions[server] }
        if dry_run
          logger.debug "transfering: #{[:up, from, to, targets, options.merge(:logger => logger).inspect ] * ', '}"
        else
          stat = File.stat(from)
          chdcksum_cmd = fetch(:java_checksum_cmd, 'md5sum')
          checksum = run_locally("( cd #{File.dirname(from)} && #{checksum_cmd} #{File.basename(from)} )").strip
          targets = targets.reject { |ssh|
            begin
              sftp = Net::SFTP::Session.new(ssh).connect!
              remote_stat = sftp.stat!(to)
              if stat.size == remote_stat.size
                remote_checksum = ssh.exec!("( cd #{File.dirname(to)} && #{checksum_cmd} #{File.basename(to)} )").strip
                checksum == remote_checksum # skip upload if file size and checksum are same between local and remote
              else
                false
              end
            rescue Net::SFTP::StatusException
              false # upload again if the remote file is absent
            end
          }
          Capistrano::Transfer.process(:up, from, to, targets, options.merge(:logger => logger), &block)
        end
      }
      if mode
        mode = mode.is_a?(Numeric) ? mode.to_s(8) : mode.to_s
        run("chmod #{mode} #{to}", options)
      end
    end

    def extract_archive(archive, destination)
      case archive
      when /\.bin$/
        "( cd #{File.dirname(destination)} && yes | sh #{archive} )"
      when /\.dmg$/
        if java_update_number
          pkg = File.join("/Volumes",
                          "JDK %d Update %02d" % [java_major_version, java_update_number],
                          "JDK %d Update %02d.pkg" % [java_major_version, java_update_number])
        else
          pkg = File.join("/Volumes",
                          "JDK %d" % [java_major_version],
                          "JDK %d" % [java_major_version])
        end
        execute = []
        execute << "open #{archive.dump}"
        execute << "( while ! test -f #{pkg.dump}; do sleep 1; done )"
        execute << "open #{pkg.dump}"
        execute << "( while ! test -d #{destination.dump}; do sleep 1; done )"
        execute.join(' && ')
      when /\.(tar\.(gz|bz2)|tgz|tbz2)$/
        "tar xf #{archive} -C #{File.dirname(destination)}"
      when /\.zip$/
        "( cd #{File.dirname(destination)} && unzip #{archive} )"
      else
        abort("Unknown archive type: #{archive}")
      end
    end

    def self.extended(configuration)
      configuration.load {
        namespace(:java) {
          ## JDK installation path settings
          _cset(:java_tools_path) {
            File.join(shared_path, 'tools', 'java')
          }
          _cset(:java_tools_path_local) {
            File.join(File.expand_path('.'), 'tools', 'java')
          }
          _cset(:java_home) {
            case java_deployee_platform
            when /Mac OS X/i
              if java_update_number
                File.join("/Library", "Java", "JavaVirtualMachines",
                          "jdk%s_%02d.jdk" % [java_inner_version, java_update_number],
                          "Contents", "Home")
              else
                File.join("/Library", "Java", "JavaVirtualMachines",
                          "jdk%s.jdk" % [java_inner_version],
                          "Contents", "Home")
              end
            else
              if java_update_number
                File.join(java_tools_path, "jdk%s_%02d" % [java_inner_version, java_update_number])
              else
                File.join(java_tools_path, "jdk%s" % [java_inner_version])
              end
            end
          }
          _cset(:java_home_local) {
            case java_deployer_platform
            when /Mac OS X/i
              if java_update_number
                File.join("/Library", "Java", "JavaVirtualMachines",
                          "jdk%s_%02d.jdk" % [java_inner_version, java_update_number],
                          "Contents", "Home")
              else
                File.join("/Library", "Java", "JavaVirtualMachines",
                          "jdk%s.jdk" % [java_inner_version],
                          "Contents", "Home")
              end
            else
              if java_update_number
                File.join(java_tools_path_local, "jdk%s_%02d" % [java_inner_version, java_update_number])
              else
                File.join(java_tools_path_local, "jdk%s" % [java_inner_version])
              end
            end
          }
          _cset(:java_bin) { File.join(java_home, 'bin', 'java') }
          _cset(:java_bin_local) { File.join(java_home_local, 'bin', 'java') }
          _cset(:java_cmd) { "env JAVA_HOME=#{java_home} #{java_bin}" }
          _cset(:java_cmd_local) { "env JAVA_HOME=#{java_home_local} #{java_bin_local}" }

          ## JDK version settings
          _cset(:java_version_name) {
            abort('You must specify JDK version explicitly.')
          }
          _cset(:java_version_info) {
            case java_version_name
            when /^(1\.4\.(\d+))(?:_([0-9]+))?$/ then [ $1, '1.4', $2, $3 ]
            when /^(1\.5\.(\d+))(?:_([0-9]+))?$/ then [ $1, '5', $2, $3 ]
            when /^(\d+)(?:u(\d+))?$/            then [ "1.#{$1}.0", $1, nil, $2 ]
            else
              abort("Could not parse JDK version name: #{java_version_name}")
            end
          }
          _cset(:java_inner_version) { java_version_info[0] } # e.g. "1.7.0"
          _cset(:java_major_version) { java_version_info[1] } # e.g. "7"
          _cset(:java_minor_version) { java_version_info[2] } # e.g. nil
          _cset(:java_update_number) { java_version_info[3] } # e.g. "6"
          _cset(:java_version) {
            "JDK #{java_major_version}"
          }
          _cset(:java_release) {
            case java_major_version
            when '1.4'
              if java_update_number
                "Java SE Development Kit #{java_inner_version.gsub('.', '_')}_#{java_update_number}"
              else
                "Java SE Development Kit #{java_inner_version.gsub('.', '_')}"
              end
            when '5'
              if java_update_number
                "Java SE Development Kit #{java_major_version}.#{java_minor_version} Update #{java_update_number}"
              else
                "Java SE Development Kit #{java_major_version}.#{java_minor_version}"
              end
            when '6', '7'
              if java_update_number
                "Java SE Development Kit #{java_major_version}u#{java_update_number}"
              else
                "Java SE Development Kit #{java_major_version}"
              end
            else
              abort("Unknown JDK version: #{java_major_version}")
            end
          }
          def java_platform(ostype, arch)
            case ostype
            when /^Darwin$/i
              case arch
              when /^i[3-7]86$/i, /^x86_64$/i
                'Mac OS X x64'
              else
                "Mac OS X #{arch}"
              end
            when /^Linux$/i
              case arch
              when /^i[3-7]86$/i
                'Linux x86'
              when /^x86_64$/i
                'Linux x64'
              else
                "Linux #{arch}"
              end
            when /^Solaris$/i
              case arch
              when /^sparc$/i
                "Solaris SPARC"
              when /^sparcv9$/i
                "Solaris SPARC 64-bit"
              when /^i[3-7]86$/i
                "Solaris x86"
              when /^x86_64$/i
                "Solaris x64"
              else
                "Solaris #{arch}"
              end
            end
          end

          ## hudson.tools.JDKInstaller.json
          _cset(:java_mechanize_agent) {
            Mechanize.log = ::Logger.new(STDERR)
            Mechanize.log.level = ::Logger::INFO
            agent = Mechanize.new { |agent|
              agent.user_agent = 'Mozilla/5.0 (Windows; U; MSIE 9.0; Windows NT 9.0; en-US)'
              agent.cookie_jar.add!(Mechanize::Cookie.new('gpw_e24', '.', :domain => 'oracle.com', :path => '/', :secure => false, :for_domain => true))
            }
            agent.ssl_version = :TLSv1 # we have to declare TLS version explicitly to avoid problems on LP:965371
            agent
          }
          _cset(:java_installer_json_uri) {
            # fetch :java_installer_uri first for backward compatibility
            fetch(:java_installer_uri, "http://updates.jenkins-ci.org/updates/hudson.tools.JDKInstaller.json")
          }
          _cset(:java_installer_json_cache) {
            File.join(java_tools_path_local, File.basename(URI.parse(java_installer_json_uri).path))
          }
          _cset(:java_installer_json_expires, 86400)
          _cset(:java_installer_json) {
            if File.file?(java_installer_json_cache)
              refresh = File.mtime(java_installer_json_cache) + java_installer_json_expires < Time.now
            else
              refresh = true
            end
            if refresh
              execute = []
              execute << "mkdir -p #{File.dirname(java_installer_json_cache)}"
              execute << "rm -f #{java_installer_json_cache}"
              execute << "wget --no-verbose -O #{java_installer_json_cache} #{java_installer_json_uri}"
              if dry_run
                logger.debug(execute.join(' && '))
              else
                run_locally(execute.join(' && '))
              end
            end
            json = File.read(java_installer_json_cache)
            json = json.sub(/\A[^{]*/, '').sub(/[^}]*\z/, '') # remove leading & trailing JS code from response
            JSON.load(json)
          }
          _cset(:java_version_data) {
            version = java_installer_json['version']
            abort("Unknown JSON format version: #{version}") if version != 2
            regex = Regexp.new(Regexp.quote(java_version), Regexp::IGNORECASE)
            data = java_installer_json['data']
            data.find { |datum| regex === datum['name'].strip }
          }
          _cset(:java_release_data) {
            regex = Regexp.new(Regexp.quote(java_release), Regexp::IGNORECASE)
            releases = java_version_data['releases']
            releases.find { |release| regex === release['name'].strip or regex === release['title'].strip }
          }
          _cset(:java_release_license_title) {
            java_release_data['lictitle']
          }
          def java_platform_data(regex)
            files = java_release_data['files']
            data = files.find { |data|
              regex === data['title']
            }
            abort("Not supported on specified JDK release: #{regex.inspect}") unless data
            data
          end
 
          ## settings for local machine
          _cset(:java_deployer_platform) { java_platform(`uname -s`.strip, `uname -m`.strip) }
          _cset(:java_deployer_archive_uri) {
            regex = Regexp.new(Regexp.quote(java_deployer_platform), Regexp::IGNORECASE)
            data = java_platform_data(regex)
            data['filepath']
          }
          _cset(:java_deployer_archive) {
            File.join(java_tools_path, File.basename(URI.parse(java_deployer_archive_uri).path))
          }
          _cset(:java_deployer_archive_local) {
            File.join(java_tools_path_local, File.basename(URI.parse(java_deployer_archive_uri).path))
          }

          ## settings for remote machines
          _cset(:java_deployee_platform) { java_platform(capture('uname -s').strip, capture('uname -m').strip) }
          _cset(:java_deployee_archive_uri) {
            regex = Regexp.new(Regexp.quote(java_depoyee_platform), Regexp::IGNORECASE)
            data = java_platform_data(regex)
            data['filepath']
          }
          _cset(:java_deployee_archive) {
            File.join(java_tools_path, File.basename(URI.parse(java_deployee_archive_uri).path))
          }
          _cset(:java_deployee_archive_local) {
            File.join(java_tools_path_local, File.basename(URI.parse(java_deployee_archive_uri).path))
          }

          ## license settings
          _cset(:java_accept_license, false)
          _cset(:java_license_title, nil)
          _cset(:java_oracle_username) { abort("java_oracle_username was not set") }
          _cset(:java_oracle_password) { abort("java_oracle_password was not set") }

          ## tasks
          desc("Install java locally.")
          task(:setup_locally, :except => { :no_release => true }) {
            if fetch(:java_setup_locally, false)
              transaction {
                download_locally
                install_locally
              }
            end
          }
          after 'deploy:setup', 'java:setup'

          task(:download_locally, :except => { :no_release => true }) {
            download_archive(java_deployer_archive_uri, java_deployer_archive_local)
          }

          task(:install_locally, :except => { :no_release => true}) {
            command = (<<-EOS).gsub(/\s+/, ' ')
              if ! test -d #{java_home_local}; then
                #{extract_archive(java_deployer_archive_local, java_home_local)} &&
                #{java_cmd_local} -version;
              fi;
            EOS
            if dry_run
              logger.debug(command)
            else
              run_locally(command)
            end
          }

          desc("Install java.")
          task(:setup, :roles => :app, :except => { :no_release => true }) {
            if fetch(:java_setup_remotely, true)
              transaction {
                download
                upload_archive(java_deployee_archive_local, java_deployee_archive)
                install
              }
            end
          }
          after 'deploy:setup', 'java:setup'

          task(:download, :roles => :app, :except => { :no_release => true }) {
            download_archive(java_deployee_archive_uri, java_deployee_archive_local)
          }

          task(:install, :roles => :app, :except => { :no_release => true }) {
            command = (<<-EOS).gsub(/\s+/, ' ')
              if ! test -d #{java_home}; then
                #{extract_archive(java_deployee_archive, java_home)} &&
                #{java_cmd} -version;
              fi;
            EOS
            run(command)
          }
        }
      }
    end
  end
end

if Capistrano::Configuration.instance
  Capistrano::Configuration.instance.extend(Capistrano::JDKInstaller)
end

# vim:set ft=ruby :
