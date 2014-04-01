v0.1.0 (Yamashita, Yuu)

* Add `java:setup_default_environment` task and setup `:default_environment` for installed JDK.
* Refactor JSON parser code. Separate them as `Capistrano::JDKInstaller::JDKInstaller` and friend classes.
* Remove some of parameters.
  * `:java_version`
  * `:java_release`
  * `:java_deployer_*`
  * `:java_deployee_*`

v0.1.1 (Yamashita, Yuu)

* Set up :default_environment after the loading of the recipes, not after the task start up.
