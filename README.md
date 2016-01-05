# new-hs

[![Build status](https://secure.travis-ci.org/aelve/new-hs.svg)](http://travis-ci.org/aelve/new-hs)

This is a script for creating a Haskell project and setting up everything that one usually wants to set up (well, not everything, but I'll add some features -that others use- later). To use it, download `new-hs.hs` and then put it somewhere in your `PATH` (for instance, `/usr/local/bin`):

    $ wget https://github.com/aelve/new-hs/blob/master/new-hs.hs
    $ chmod +x new-hs.hs
    $ sudo mv new-hs.hs /usr/local/bin/new-hs

After that, call `new-hs`, answer the questions, and a new project would be created in a subfolder.

To change the defaults (repository owner, default license, etc), edit the beginning of the script (the “Settings” section).

## Features

Note that the following features are currently missing:

  * supporting any VCS but Git
  * supporting anything but Github
  * creating a [Stack](http://haskellstack.org) project
  * *not* creating a repository / enabling Travis-CI / etc
  * testing on GHC HEAD

### Repository

It creates a new folder with Git repository in it, and then creates a corresponding repository on Github.

  * It creates a good .gitignore file.
  * It creates a tracking branch and makes a commit.

### Project

It generates a .cabal file using `cabal init`, and optionally creates a Cabal sandbox. It also fills in some additional fields: `tested-with`, `bug-reports`, and the `source-repository` section.

  * It enables all warnings (excluding `warn-unused-do-bind`).
  * If you have chosen to put your code into public domain, it creates a LICENSE file with [CC0](https://creativecommons.org/publicdomain/zero/1.0/legalcode).
  * It creates an empty module and a changelog.
  * It creates a readme with Travis, Hackage, and license badges.

### Travis-CI

It enables [Travis-CI](http://travis-ci.org/) for the repository and generate a .travis.yml file using hvr's [multi-ghc-travis](https://github.com/hvr/multi-ghc-travis) script.

  * It makes Travis-CI treat warnings as errors (by adding `-Werror`).

## Requirements

* GHC to run the script (7.6.3 or later)
* Git to create the repository
* cabal-install to create the project
* Github's client [`hub`](https://github.com/github/hub)
* Travis-CI's client [`travis`](https://github.com/travis-ci/travis.rb)

On Arch Linux, you can install all of those things by doing

    $ yaourt -S ghc git cabal-install hub ruby-travis
