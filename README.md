# new-hs

This is a script for creating a Haskell project:

* **create a repository on Github**
* create a comprehensive .gitignore file
* set up branch tracking

* **generate .cabal file**
* create a changelog
* create a LICENSE file with the [CC0](https://creativecommons.org/publicdomain/zero/1.0/legalcode) license if you have chosen “PublicDomain” as the license
* fill in the `tested-with` field
* fill in the `bug-reports` field
* add a `source-repository` section
* enable all warnings (excluding `warn-unused-do-bind`)
* create an empty module
* optionally create a Cabal sandbox

* **enable [Travis-CI](http://travis-ci.org/) for the repository** and generate a .travis.yml file using hvr's [multi-ghc-travis](https://github.com/hvr/multi-ghc-travis)
* make Travis-CI treat warnings as errors

## Requirements

* GHC to run the script
* Git to create the repository
* cabal-install to create the project
* Github's client [`hub`](https://github.com/github/hub)
* Travis-CI's client [`travis`](https://github.com/travis-ci/travis.rb)

On Arch Linux, you can install all of those things by doing

    $ yaourt -S ghc git cabal-install hub ruby-travis
