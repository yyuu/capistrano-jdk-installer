# capistrano-jdk-installer

a capistrano recipe to download and install JDK for your projects.

## Installation

Add this line to your application's Gemfile:

    gem 'capistrano-jdk-installer'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install capistrano-jdk-installer

## Usage

This recipes will try to do following things during Capistrano `deploy:setup`.

1. Download JDK information from [updates.jenkins-ci.org](http://updates.jenkins-ci.org/updates/hudson.tools.JDKInstaller.json)
2. Download JDK archive
3. Install JDK for your project remotely (default) and/or locally

To enable this recipe, add following in your `config/deploy.rb`.

    # in "config/deploy.rb"
    require 'capistrano-jdk-installer'
    set(:java_version_name, "7u6")
    set(:java_oracle_username, "foo@example.com") # your ID on oracle.com
    set(:java_oracle_password, "setcret") # your password on oracle.com
    set(:java_license_title, "Oracle Binary Code License Agreement for Java SE")
    set(:java_accept_license, true)

Following options are available to manage your JDK installation.

 * `:java_version_name` - preferred JDK version. this value must be defined in JSON response from `:java_installer_uri`.
 * `:java_oracle_username` - your credential to be used to download JDK archive from oracle.com.
 * `:java_oracle_password` - your credential to be used to download JDK archive from oracle.com.
 * `:java_license_title` - the license title of JDK which you will accept.
 * `:java_accept_license` - specify whether you accept the JDK license. `false` by default.
 * `:java_setup_locally` - specify whether you want to setup JDK on local machine. `false` by default.
 * `:java_setup_remotely` - specify whether you want to setup JDK on remote machines. `true` by default.
 * `:java_installer_uri` - `http://updates.jenkins-ci.org/updates/hudson.tools.JDKInstaller.json` by default.
 * `:java_installer_json_cache` - the cache file path of "hudson.tools.JDKINstaller.json".
 * `:java_installer_json_expires` - the cache TTL. cache `86400` seconds by default.
 * `:java_home` - the path to the `JAVA_HOME` on remote machines.
 * `:java_home_local` - the path to the `JAVA_HOME` on local machine.
 * `:java_cmd` - the `java` command on remote machines.
 * `:java_cmd_local` - the `java` command on local machine.
 * `:java_checksum_cmd` - use specified command to compare JDK archives. use `md5sum` by default.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request

## Author

- YAMASHITA Yuu (https://github.com/yyuu)
- Geisha Tokyo Entertainment Inc. (http://www.geishatokyo.com/)

## License

MIT
