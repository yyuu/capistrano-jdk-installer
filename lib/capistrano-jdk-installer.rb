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
      run("mkdir -p #{File.dirname(to)}")
      execute_on_servers(options) { |servers|
        targets = servers.map { |server| sessions[server] }
        if dry_run
          logger.debug "transfering: #{[:up, from, to, targets, options.merge(:logger => logger).inspect ] * ', '}"
        else
          stat = File.stat(from)
          checksum_cmd = fetch(:java_checksum_cmd, 'md5sum')
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
      when /\.(bin|sh)$/
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
            case java_deployee_file
            when /macosx/i
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
            case java_deployer_file
            when /macosx/i
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
            when /^(1\.4\.(\d+))(?:[_u]([0-9]+))?$/ then [ $1, '1.4', $2, $3 ]
            when /^(1\.5\.(\d+))(?:[_u]([0-9]+))?$/ then [ $1, '5', $2, $3 ]
            when /^(\d+)(?:u(\d+))?$/               then [ "1.#{$1}.0", $1, 0, $2 ]
            else
              abort("Could not parse JDK version name: #{java_version_name}")
            end
          }
          _cset(:java_inner_version) { java_version_info[0] } # e.g. "1.7.0"
          _cset(:java_major_version) { java_version_info[1] } # e.g. 7
          _cset(:java_minor_version) { java_version_info[2] } # e.g. 0
          _cset(:java_update_number) { java_version_info[3] } # e.g. 6
          _cset(:java_version) {
            "JDK #{java_major_version}"
          }
          _cset(:java_release) {
            case java_major_version
            when '1.4', '5'
              jdk = java_major_version == '1.4' ? 'j2sdk' : 'jdk'
              if java_update_number
                '%s-%s_%02d-oth-JPR' % [jdk, java_inner_version, java_update_number]
              else
                '%s-%s-oth-JPR' % [jdk, java_inner_version]
              end
            else
              if java_update_number
                'jdk-%du%d-oth-JPR' % [java_major_version, java_update_number]
              else
                'jdk-%d-oth-JPR' % [java_major_version]
              end
            end
          }
          def java_platform(ostype, arch)
            case ostype
            when /^Darwin$/i
              case arch
              when /^i[3-7]86$/i, /^x86_64$/i
                "macosx-x64"
              else
                "macosx-#{arch.downcase}"
              end
            when /^Linux$/i
              case arch
              when /^i[3-7]86$/i
                "linux-i586"
              when /^x86_64$/i
                case java_major_version
                when '1.4', '5'
                  "linux-amd64"
                else
                  "linux-x64"
                end
              else
                "linux-#{arch.downcase}"
              end
            when /^Solaris$/i
              case arch
              when /^sparc$/i
                "solaris-sparc"
              when /^sparcv9$/i
                "solaris-sparcv9"
              when /^i[3-7]86$/i
                "solaris-i586"
              when /^x86_64$/i
                "solaris-x64"
              else
                "solaris-#{arch.downcase}"
              end
            end
          end
          def java_file(ostype, arch)
            case java_major_version
            when '1.4', '5'
              jdk = java_major_version == '1.4' ? 'j2sdk' : 'jdk'
              if java_update_number
                '%s-%s_%02d-%s' % [jdk, java_inner_version.gsub('.', '_'), java_update_number, java_platform(ostype, arch)]
              else
                '%s-%s-%s' % [jdk, java_inner_version.gsub('.', '_'), java_platform(ostype, arch)]
              end
            else
              if java_update_number
                'jdk-%du%d-%s' % [java_major_version, java_update_number, java_platform(ostype, arch)]
              else
                'jdk-%d-%s' % [java_major_version, java_platform(ostype, arch)]
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
          _cset(:java_installer_json_keep_stale, true) # keep staled cache even if wget fails
          _cset(:java_installer_json) {
            # should not update cache directly from wget.
            # wget will save response to the file even if the request fails.
            tempfile = "#{java_installer_json_cache}.#{$$}"
            begin
              if not File.file?(java_installer_json_cache) or File.mtime(java_installer_json_cache)+java_installer_json_expires < Time.now
                execute = []
                execute << "mkdir -p #{File.dirname(java_installer_json_cache)}"
                success_cmd = "mv -f #{tempfile} #{java_installer_json_cache}"
                failure_cmd = java_installer_json_keep_stale ? 'true' : 'false'
                execute << "( wget --no-verbose -O #{tempfile} #{java_installer_json_uri} && #{success_cmd} || #{failure_cmd} )"

                if dry_run
                  logger.debug(execute.join(' && '))
                else
                  run_locally(execute.join(' && '))
                end
              end
              abort("No such file: #{java_installer_json_cache}") unless File.file?(java_installer_json_cache)
              json = File.read(java_installer_json_cache)
              json = json.sub(/\A[^{]*/, '').sub(/[^}]*\z/, '').strip # remove leading & trailing JS code from response
              JSON.load(json)
            ensure
              run_locally("rm -f #{tempfile}") unless dry_run
            end
          }
          _cset(:java_version_data) {
            version = java_installer_json['version']
            abort("Unknown JSON format version: #{version}") if version != 2
            regex = Regexp.new(Regexp.quote(java_version), Regexp::IGNORECASE)
            data = java_installer_json['data']
            logger.info("Requested JDK version is #{java_version.dump}.")
            data.find { |datum|
              logger.debug("Checking JDK version: #{datum['name'].strip}")
              regex === datum['name'].strip
            }
          }
          _cset(:java_release_data) {
            abort("No such JDK version found: #{java_version}") unless java_version_data
            regex = Regexp.new(Regexp.quote(java_release), Regexp::IGNORECASE)
            releases = java_version_data['releases']
            logger.info("Requested JDK release is #{java_release.dump}.")
            releases.find { |release|
              logger.debug("Checking JDK release: #{release['title'].strip} (#{release['name'].strip})")
              regex === release['name'].strip or regex === release['title'].strip
            }
          }
          _cset(:java_release_license_title) {
            abort("No such JDK release found: #{java_version}/#{java_release}") unless java_release_data
            java_release_data['lictitle']
          }
          def java_file_data(name)
            abort("No such JDK release found: #{java_version}/#{java_release}") unless java_release_data
            regex = Regexp.new(Regexp.quote(name.to_s), Regexp::IGNORECASE)
            logger.info("Requested JDK file is #{name.dump}.")
            files = java_release_data['files']
            files.find { |data|
              logger.debug("Checking JDK file: #{data['title'].strip} (#{data['name'].strip})")
              regex === data['name'] or regex === data['title']
            }
          end
 
          ## settings for local machine
          _cset(:java_deployer_file) {
            java_file(`uname -s`.strip, `uname -m`.strip)
          }
          _cset(:java_deployer_archive_uri) {
            data = java_file_data(java_deployer_file)
            abort("No such JDK release found for specified platform: #{java_version}/#{java_release}/#{java_deployer_file}") unless data
            data['filepath']
          }
          _cset(:java_deployer_archive) {
            File.join(java_tools_path, File.basename(URI.parse(java_deployer_archive_uri).path))
          }
          _cset(:java_deployer_archive_local) {
            File.join(java_tools_path_local, File.basename(URI.parse(java_deployer_archive_uri).path))
          }

          ## settings for remote machines
          _cset(:java_deployee_file) {
            java_file(capture('uname -s').strip, capture('uname -m').strip)
          }
          _cset(:java_deployee_archive_uri) {
            data = java_file_data(java_deployee_file)
            abort("No such JDK release found for specified platform: #{java_version}/#{java_release}/#{java_deployee_file}") unless data
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
            transaction {
              download_locally
              install_locally
            }
          }

          task(:download_locally, :except => { :no_release => true }) {
            download_archive(java_deployer_archive_uri, java_deployer_archive_local)
          }

          task(:install_locally, :except => { :no_release => true}) {
            command = (<<-EOS).gsub(/\s+/, ' ').strip
              if ! test -d #{java_home_local}; then
                #{extract_archive(java_deployer_archive_local, java_home_local)} &&
                ( #{java_cmd_local} -version || rm -rf #{java_home_local} ) &&
                test -d #{java_home_local};
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
                setup_locally if fetch(:java_setup_locally, false)
              }
            end
          }
          after 'deploy:setup', 'java:setup'

          task(:download, :roles => :app, :except => { :no_release => true }) {
            download_archive(java_deployee_archive_uri, java_deployee_archive_local)
          }

          task(:install, :roles => :app, :except => { :no_release => true }) {
            command = (<<-EOS).gsub(/\s+/, ' ').strip
              if ! test -d #{java_home}; then
                #{extract_archive(java_deployee_archive, java_home)} &&
                ( #{java_cmd} -version || rm -rf #{java_home} ) &&
                test -d #{java_home};
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
