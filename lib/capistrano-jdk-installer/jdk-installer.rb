#!/usr/bin/env ruby

require "capistrano-jdk-installer/version"
require "fileutils"
require "json"
require "logger"
require "mechanize"
require "uri"

module Capistrano
  module JDKInstaller
    class JDKInstallerError < StandardError
    end

    class JDKInstallerParseError < JDKInstallerError
    end

    class JDKInstallerFile
      MECHANIZE_USER_AGENT = "Mozilla/5.0 (Windows; U; MSIE 9.0; Windows NT 9.0; en-US)"
      def initialize(release, data, options={})
        @release = release
        @data = data
        @options = options.dup
        @logger = @options[:logger]
      end
      attr_reader :release, :options

      def logger
        @logger ||= Logger.new(STDOUT)
      end

      def filepath
        @filepath ||= @data["filepath"]
      end
      alias file filepath

      def name
        @name ||= @data["name"]
      end
      alias to_s name

      def title
        @title ||= @data["title"]
      end

      def platform
        @platform ||= case name
                      when /jdk-\d+(?:u\d+)?-(\w+-\w+)\.\w+/           then $1.downcase
                      when /j2?dk-\d+_\d+_\d+(?:_\d+)?-(\w+-\w+)\.\w+/ then $1.downcase
                      else
                        raise(JDKInstallerParseError.new("Could not parse JDK file name: #{name}"))
                      end
      end

      def version
        release.version
      end

      def major_version
        release.major_version
      end

      def minor_version
        release.minor_version
      end

      def update_number
        release.update_number
      end

      def inner_version
        release.inner_version
      end

      def licpath
        release.licpath
      end
      alias license_path licpath

      def lictitle
        release.lictitle
      end
      alias license_title lictitle

      def mechanize
        @mechanize ||= ::Mechanize.new { |agent|
          agent.user_agent = MECHANIZE_USER_AGENT
          agent.cookie_jar.add!(Mechanize::Cookie.new("gpw_e24", ".", :domain => "oracle.com", :path => "/", :secure => false, :for_domain => true))
          agent.ssl_version = :TLSv1 # we have to declare TLS version explicitly to avoid problems on LP:965371
        }
      end

      def download(filename, options={})
        options = @options.merge(options)
        username = options.fetch(:username, "")
        password = options.fetch(:password, "")

        logger.debug("Download JDK archive from #{filepath}....")
        page = mechanize.get(filepath)
        1.upto(16) do # to avoid infinity loop...
          if page.uri.host == "login.oracle.com" # login.oracle.com doesn't return proper Content-Type
            if page.is_a?(::Mechanize::File)
              page = ::Mechanize::Page.new(page.uri, page.response, page.body, page.code, mechanize)
            end
            form = page.form_with
            form["ssousername"] = username
            form["password"] = password
            page = mechanize.submit(form)
          else
            page.save(filename)
            logger.debug("Wrote #{page.body.size} bytes to #{filename}.")
            break
          end
        end
      end

      def uri
        @uri ||= URI.parse(filepath)
      end

      def basename
        File.basename(uri.path)
      end

      def install_path(options={})
        options = @options.merge(options)
        case platform
        when /macosx/i
          v = if update_number
                "jdk%s_%02d.jdk" % [inner_version, update_number]
              else
                "jdk%s.jdk" % [inner_version]
              end
          File.join("/Library", "Java", "JavaVirtualMachines", v, "Contents", "Home")
        else
          v = if update_number
                "jdk%s_%02d" % [inner_version, update_number]
              else
                "jdk%s" % [inner_version]
              end
          if options.key?(:path)
            File.join(options[:path], v)
          else
            v
          end
        end
      end

      def install_command(filename, destination, options={})
        execute = []
        execute << "mkdir -p #{File.dirname(destination).dump}"
        case filename
        when /\.(bin|sh)$/
          execute << "( cd #{File.dirname(destination).dump} && yes | sh #{filename.dump} )"
        when /\.dmg$/
          if update_number
            pkg = File.join("/Volumes", "JDK %d Update %02d" % [major_version, update_number],
                            "JDK %d Update %02d.pkg" % [major_version, update_number])
          else
            pkg = File.join("/Volumes", "JDK %d" % [major_version], "JDK %d" % [major_version])
          end
          execute << "open #{filenamedump}"
          execute << "( while test \! -f #{pkg.dump}; do sleep 1; done )"
          execute << "open #{pkg.dump}"
          execute << "( while test \! -d #{destination.dump}; do sleep 1; done )"
        when /\.(tar\.(gz|bz2)|tgz|tbz2)$/
          execute << "tar xf #{filename.dump} -C #{File.dirname(destination).dump}"
        when /\.zip$/
          execute << "( cd #{File.dirname(destination).dump} && unzip #{filename.dump} )"
        else
          execute << "true"
        end
        execute.join(" && ")
      end
    end

    class JDKInstallerRelease
      include Enumerable
      def initialize(version, data, options={})
        @version = version
        @data = data
        @options = options.dup
        @logger = @options[:logger]
      end
      attr_reader :version, :options

      def logger
        @logger ||= Logger.new(STDOUT)
      end

      def files
        @files ||= @data["files"].map { |file|
          JDKInstallerFile.new(self, file, @options)
        }
      end
      alias to_a files

      def each(&block)
        self.to_a.each(&block)
      end

      def find_by_platform(platform)
        platform = platform.to_s
        self.find { |f| f.platform == platform }
      end

      def licpath
        @licpath ||= @data["licpath"]
      end
      alias license_path licpath

      def lictitle
        @lictitle ||= @data["lictitle"]
      end
      alias license_title lictitle

      def name
        @name ||= @data["name"]
      end
      alias to_s name

      def title
        @title ||= @data["title"]
      end

      def version_info
        @version_info ||= case name
          when /j2sdk-(1\.4\.(\d+))(?:[_u]([0-9]+))?/ then [ $1, "1.4", $2, $3 ]
          when /jdk-(1\.5\.(\d+))(?:[_u]([0-9]+))?/   then [ $1, "5", $2, $3 ]
          when /jdk-(\d+)(?:u(\d+))?/                 then [ "1.#{$1}.0", $1, 0, $2 ]
          else
            raise(JDKInstallerParseError.new("Could not parse JDK release name: #{name}"))
          end
      end

      def inner_version
        @inner_version ||= version_info[0] # e.g. "1.7.0"
      end

      def major_version
        @major_version ||= version_info[1] # e.g. "7"
        if @major_version != version.major_version
          raise(JDKInstallerParseError.new("Major version mismatch (got=#{@major_version}, expected=#{version.major_version})"))
        end
        @major_version
      end

      def minor_version
        @minor_version ||= version_info[2] # e.g. "0"
      end

      def update_number
        @update_number ||= version_info[3] # e.g. "6"
      end
    end

    class JDKInstallerVersion
      include Enumerable
      def initialize(data, options={})
        @data = data
        @options = options.dup
        @logger = @options[:logger]
      end
      attr_reader :options

      def logger
        @logger ||= Logger.new(STDOUT)
      end

      def name
        @name ||= @data["name"]
      end
      alias to_s name

      def releases
        @releases ||= @data["releases"].map { |release|
          JDKInstallerRelease.new(self, release, @options)
        }
      end
      alias to_a releases

      def each(&block)
        self.to_a.each(&block)
      end

      def find_by_update_number(update_number, options={})
        update_number = update_number.to_s
        self.find { |r| r.update_number == update_number }
      end

      def major_version
        case name
        when /JDK ((?:\d+\.)?\d+)/i then $1
        else
          raise(JDKInstallerParseError.new("Could not parse JDK version name: #{name}"))
        end
      end
    end

    class JDKInstallerVersions
      include Enumerable
      JSON_VERSION = 2
      class << self
        def parse(s, options={})
          s = s.sub(/\A[^{]*/, "").sub(/[^}]*\z/, "").strip # remove leading & trailing JS code from response
          i = new(JSON.load(s), options)
          i.versions
        end
      end

      def initialize(data, options={})
        @data = data
        @options = options.dup
        @logger = @options[:logger]

        if @data["version"] != JSON_VERSION
          raise(JDKInstallerParseError.new("JSON version mismatch (got=#{@data["version"]}, expected=#{JSON_VERSION})"))
        end
      end
      attr_reader :options

      def logger
        @logger ||= Logger.new(STDOUT)
      end

      def versions
        @versions ||= @data["data"].map { |version|
          JDKInstallerVersion.new(version, @options)
        }
      end
      alias to_a versions

      def each(&block)
        self.to_a.each(&block)
      end

      def find_by_major_version(version, options={})
        version = version.to_s
        self.find { |v| v.major_version == version }
      end
    end

    class JDKInstaller
      JDK_INSTALLER_URI = "http://updates.jenkins-ci.org/updates/hudson.tools.JDKInstaller.json"
      JDK_INSTALLER_TTL = 259200
      class << self
        def platform_string(ostype, arch, options={})
          ostype = ostype.to_s.strip.downcase
          arch = arch.to_s.strip.downcase
          case ostype
          when /^Darwin$/i
            case arch
            when /^(?:i[3-7]86|x86_64)$/ then "macosx-x64"
            else
              "macosx-#{arch}"
            end
          when /^Linux$/i
            case arch
            when /^i[3-7]86$/i         then "linux-i586"
            when /^(?:amd64|x86_64)$/i then "linux-x64"
            else
              "linux-#{arch}"
            end
          when /^Solaris$/i
            case arch
            when /^sparc$/i    then "solaris-sparc"
            when /^sparcv9$/i  then "solaris-sparcv9"
            when /^i[3-7]86$/i then "solaris-i586"
            when /^x86_64$/i   then "solaris-x64"
            else
              "solaris-#{arch}"
            end
          end
        end
      end

      def initialize(options={})
        @uri = ( options.delete(:uri) || JDK_INSTALLER_URI )
        @ttl = ( options.delete(:ttl) || JDK_INSTALLER_TTL )
        @file = if options.key?(:file)
                  options.delete(:file)
                else
                  Tempfile.new("jdk-installer")
                end
        @keep_stale = options.fetch(:keep_stale, false)
        @options = options.dup
        @logger = @options[:logger]
        update
      end

      def logger
        @logger ||= Logger.new(STDOUT)
      end

      def mechanize
        @mechanize ||= ::Mechanize.new { |agent|
          agent.ssl_version = :TLSv1 # we have to declare TLS version explicitly to avoid problems on LP:965371
        }
      end

      def expired?(t=Time.now)
        not(File.file?(@file)) or ( File.mtime(@file) + @ttl < t )
      end

      def update
        if expired?
          logger.info("The cache of JDKInstaller.json has been expired. (ttl=#{@ttl})")
          update!
        end
      end


      def update!
        begin
          page = mechanize.get(@uri)
          write(page.body)
        rescue ::Mechanize::Error => error
          logger.info("Could not update JDKInstaller.json from #{@uri}. (#{error})")
          if @keep_stale
            logger.info("Try to use stale JDKInstaller.json at #{@file}.")
          else
            raise
          end
        end
      end


      def write(s)
        if @file.respond_to?(:write)
          @file.write(s)
        else
          FileUtils.mkdir_p(File.dirname(@file))
          File.write(@file, s)
        end
      end

      def read()
        if @file.respond_to?(:read)
          @file.read
        else
          File.read(@file)
        end
      end

      def versions
        @versions ||= JDKInstallerVersions.parse(read, @options)
      end

      def releases
        @releases ||= versions.map { |version| version.releases }.flatten
      end

      def files
        @files ||= releases.map { |release| release.files }.flatten
      end

      def [](regex)
        files.find { |file| regex === file.to_s }
      end
    end
  end
end

# vim:set ft=ruby sw=2 ts=2 :
