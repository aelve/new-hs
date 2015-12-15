# new-hs

This is a script for creating a Haskell project.

### Repository

It creates a new folder with Git repository in it, and then creates a corresponding repository on Github.

Minor stuff:

  * It creates a good .gitignore file.
  * It sets up branch tracking (so that `git pull` would work automatically).

### Cabal

It generates a .cabal file using `cabal init`, and optionally creates a Cabal sandbox. It also fills in some additional fields:

  * the `tested-with` field
  * the `bug-reports` field
  * the `source-repository` section

Minor stuff:

  * It enables all warnings (excluding `warn-unused-do-bind`).
  * It creates an empty module and a changelog.
  * If you have chosen to put your code into public domain, it creates a LICENSE file with [CC0](https://creativecommons.org/publicdomain/zero/1.0/legalcode).

### Travis-CI

It enables [Travis-CI](http://travis-ci.org/) for the repository and generate a .travis.yml file using hvr's [multi-ghc-travis](https://github.com/hvr/multi-ghc-travis) script.

Minor stuff:

  * It makes Travis-CI treat warnings as errors (by adding `-Werror`).

## Requirements

* GHC to run the script
* Git to create the repository
* cabal-install to create the project
* Github's client [`hub`](https://github.com/github/hub)
* Travis-CI's client [`travis`](https://github.com/travis-ci/travis.rb)

On Arch Linux, you can install all of those things by doing

    $ yaourt -S ghc git cabal-install hub ruby-travis
