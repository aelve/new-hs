#!/usr/bin/env runghc


{-# OPTIONS_GHC -fno-warn-orphans #-}


{-# LANGUAGE
OverloadedStrings,
FlexibleInstances,
TypeFamilies,
ScopedTypeVariables,
MultiWayIf
  #-}


import Control.Exception
import Control.Monad
import Control.Monad.Trans.State
import Data.List
import Data.String
import System.Directory
import System.Exit
import System.Process
import Text.Printf


-- Settings

defaultOwner :: String
defaultOwner = "aelve"

defaultLicense :: String
defaultLicense = "BSD3"

defaultGHC :: String
defaultGHC = "7.8.4 7.10.3"

-- The main script.

main :: IO ()
main = do
  -- Create a repository.
  owner <- queryDef "Repository owner?" defaultOwner
  repo <- query "Repository?"
  "mkdir" [repo]
  "cd" [repo]
  "git" ["init"]
  -- Create the repository on Github.
  description <- query "Short project description?"
  "hub" ["create", "-d", description, printf "%s/%s" owner repo]
  -- Create a .gitignore.
  writeFile ".gitignore" gitignore
  -- Generate the project.
  generateProject owner repo description
  -- Create Cabal sandbox.
  ask "Create Cabal sandbox?" [
    "n" ==> return (),
    "y" ==> "cabal" ["sandbox", "init"] ]
  -- Create a .travis.yml file and enable Travis.
  "travis" ["enable"]
  generateTravis repo
  -- Make a commit and push it.
  "git" ["add", "."]
  "git" ["commit", "-m", "Create the project"]
  "git" ["push", "-u", "origin"]

-- | Generate the project.
generateProject :: String -> String -> String -> IO ()
generateProject owner repo description = do
  mapM_ putStrLn [
    "Here are some categories:",
    "",
    "  * Control                    * Concurrency",
    "  * Codec                      * Graphics",
    "  * Data                       * Sound",
    "  * Math                       * System",
    "  * Parsing                    * Network",
    "  * Text",
    "",
    "  * Application                * Development",
    "  * Compilers/Interpreters     * Testing",
    "  * Web",
    "  * Game",
    "  * Utility",
    ""]
  category <- query "Category?"
  licenseCabal <- choose "License?"
    (nub (defaultLicense : words "BSD3 BSD2 GPL-3 GPL-2 MIT PublicDomain"))
  when (licenseCabal == "PublicDomain") $ do
    putStrLn "Cabal doesn't have a preferred public domain license;"
    putStrLn "generating a LICENSE file with CC0."
    writeFile "LICENSE" publicDomainLicense
  (isLib, _isExe) <- ask "Library or executable?" [
    "lib"  ==> return (True, False),
    "exe"  ==> return (False, True),
    "both" ==> return (True, True) ]
  let defCabalFlags = [
        "--non-interactive",
        "--no-comments",
        "--synopsis", description,
        "--homepage", printf "http://github.com/%s/%s" owner repo,
        "--category", category,
        "--license", licenseCabal,
        -- “file” instead of “files” is not a typo, look at cabal init --help
        "--extra-source-file", "CHANGELOG.md" ]
  if isLib then do
    someModule <- query "Some module name?"
    "cabal" $
      ["init"] ++ defCabalFlags ++
      ["--is-library",
       "--source-dir", "lib",
       "--expose-module", someModule ]
    let moduleName = last (splitOn "." someModule)
        moduleDir  = intercalate "/" ("lib" : init (splitOn "." someModule))
    "mkdir" ["-p", moduleDir]
    writeFile (printf "%s/%s.hs" moduleDir moduleName) (emptyModule someModule)
  else do
    "cabal" $
      ["init"] ++ defCabalFlags ++
      ["--is-executable",
       "--source-dir", "src" ]
    "mkdir" ["-p", "src"]
    writeFile "src/Main.hs" mainModule
  -- Cabal prints “You may want to edit the .cabal file and add a Description
  -- field.”, but we'll add it by ourselves.
  putStrLn "Note: new-hs will add a description field automatically,"
  putStrLn "there's no need to edit the .cabal file."

  let license = if licenseCabal == "PublicDomain" then "CC0" else licenseCabal

  -- Edit the .cabal file.
  let cabalName = printf "%s.cabal" repo
  cabalFile <- readFile' cabalName
  -- TODO: once GHC 7.8 is dropped, switch to <$>
  testedVersions <- words `fmap`
    queryDef "Versions of GHC to test with? (space-separated)" defaultGHC
  longDescription <-
    (\s -> if s == "repo description" then description else s) `fmap`
    queryDef "Longer description?" "repo description"
  writeFile cabalName $ flip execState cabalFile $ do
    -- Remove the “generated with cabal” comment.
    modify $ overSectionList tail
    -- Add a source-repository section.
    let sourceRepo = unlines [
          "source-repository head",
          "  type:                git",
          printf "  location:            git://github.com/%s/%s.git"
            owner repo ]
    modify $ overSectionList (\(p:ps) -> (p:sourceRepo:ps))
    -- Add a bug-reports field.
    let bugReports =
          printf "bug-reports:         http://github.com/%s/%s/issues"
            owner repo
    modify $ inMainSection $ \p ->
      let (l, x:r) = break ("homepage" ~==) (lines p)
      in  unlines (l ++ [x, bugReports] ++ r)
    -- Add a tested-with field.
    let testedWith = "tested-with:         " ++
          intercalate ", " (map ("GHC == " ++) testedVersions)
    modify $ inMainSection $ \p ->
      let (l, x:r) = break ("category" ~==) (lines p)
      in  unlines (l ++ [x, testedWith] ++ r)
    -- Add a longer description.
    let desc1 = "description:"
        desc2 = "  " ++ longDescription
    modify $ inMainSection $ \p ->
      let (l, _:r) = break ("-- description" ~==) (lines p)
      in  unlines (l ++ [desc1, desc2] ++ r)
    -- Enable warnings.
    let ghcOptions = "  ghc-options:         -Wall -fno-warn-unused-do-bind"
    modify $ inEachSection $ \p ->
      if "hs-source-dirs" =~= p
        then let (l, x:r) = break ("  hs-source-dirs" ~==) (lines p)
             in  unlines (l ++ [ghcOptions, x] ++ r)
        else p

  -- Create a changelog and a readme.
  writeFile "CHANGELOG.md" changelog
  writeFile "README.md" (readme owner repo license)

  -- Use Cabal to check the resulting file.
  "cabal" ["check"]

-- | Generate Travis-CI file.
generateTravis :: String -> IO ()
generateTravis repo = do
  let travisName = ".travis.yml"
  "wget" ["https://raw.githubusercontent.com/hvr/multi-ghc-travis\
          \/master/make_travis_yml.hs"]
  "chmod" ["+x", "make_travis_yml.hs"]
  callCommand' (printf "./make_travis_yml.hs %s.cabal > %s" repo travisName)
  "rm" ["make_travis_yml.hs"]

  -- Edit the .travis.yml file.
  travisFile <- readFile' travisName
  writeFile travisName $ flip execState travisFile $ do
    -- Don't tolerate warnings.
    let werror = "- cabal build --ghc-options=-Werror"
    modify $ inEachSection $ \p ->
      if "script:" =~= p
        then replace "- cabal build" werror p
        else p

-- Utilities.

overSectionList :: ([String] -> [String]) -> String -> String
overSectionList f = unparagraphs . f . paragraphs

inMainSection :: (String -> String) -> String -> String
inMainSection f = overSectionList (\(p:ps) -> f p : ps)

inEachSection :: (String -> String) -> String -> String
inEachSection f = overSectionList (map f)

-- TODO: once GHC 7.6 is dropped, just use callCommand
callCommand' :: String -> IO ()
callCommand' cmd = do
  exit_code <- system cmd
  case exit_code of
    ExitSuccess   -> return ()
    ExitFailure r -> error $ printf "%s failed with exit code %d" cmd r

-- This is needed to be able to call commands by writing strings.
instance (a ~ String, b ~ ()) => IsString ([a] -> IO b) where
  fromString "cd" [arg] = setCurrentDirectory arg
  fromString cmd args = callCommand' (showCommandForUser cmd args)

printQuestion :: String -> [String] -> IO ()
printQuestion question (def:rest) =
  printf "%s [%s]%s " question def (concat (map ('/':) rest))
printQuestion question [] =
  printf "%s " question

ask :: String -> [(String, IO a)] -> IO a
ask question choices = do
  printQuestion question (map fst choices)
  answer <- getLine
  if | null answer ->
         snd (head choices)
     | Just action <- lookup answer choices ->
         action
     | otherwise -> do
         putStrLn "This wasn't a valid choice."
         ask question choices

choose :: String -> [String] -> IO String
choose question choices = do
  printQuestion question choices
  answer <- getLine
  if | null answer ->
         return (head choices)
     | answer `elem` choices ->
         return answer
     | otherwise -> do
         putStrLn "This wasn't a valid choice."
         choose question choices

query :: String -> IO String
query question = do
  printf "%s " question
  answer <- getLine
  if | null answer -> do
         putStrLn "An answer is required."
         query question
     | otherwise ->
         return answer

queryDef :: String -> String -> IO String
queryDef question defAnswer = do
  printf "%s [%s] " question defAnswer
  answer <- getLine
  if | null answer ->
         return defAnswer
     | otherwise ->
         return answer

(==>) :: a -> b -> (a, b)
(==>) = (,)

(~==), (=~=) :: String -> String -> Bool
(~==) = isPrefixOf
(=~=) = isInfixOf

splitOn :: String -> String -> [String]
splitOn _   ""  = []
splitOn sep str = go "" str
  where
    sepLen = length sep
    go acc s
      | null s && null acc = [""]
      | null s             = [reverse acc]
      | sep ~== s          = reverse acc : go "" (drop sepLen s)
      | otherwise          = go (head s : acc) (tail s)

replace :: String -> String -> String -> String
replace old new = intercalate new . splitOn old

-- | Separate paragraphs with blank lines.
unparagraphs :: [String] -> String
unparagraphs =
  intercalate "\n" . map (++ "\n") .
  map (dropWhile (== '\n')) . map (dropWhileEnd (== '\n'))

paragraphs :: String -> [String]
paragraphs = splitOn "\n\n"

-- | A strict 'readFile'.
readFile' :: FilePath -> IO String
readFile' path = do
  x <- readFile path
  evaluate (length x)
  return x

{-

Table of contents:

  * gitignore
  * changelog
  * readme
  * emptyModule
  * mainModule
  * publicDomainLicense

-}

gitignore :: String
gitignore = unlines [
  "dist",
  "cabal-dev",
  "*.o",
  "*.hi",
  "*.chi",
  "*.chs.h",
  "*.dyn_o",
  "*.dyn_hi",
  "*.prof",
  "*.aux",
  "*.hp",
  ".virtualenv",
  ".hsenv",
  ".hpc",
  ".stack-work/",
  ".cabal-sandbox/",
  "cabal.sandbox.config",
  "cabal.config",
  "TAGS",
  ".DS_Store",
  "*~",
  "*#" ]

changelog :: String
changelog = unlines [
  "# 0.1.0.0",
  "",
  "First release."]

readme :: String -> String -> String -> String
readme owner repo license = unlines $ [
  printf "# %s" repo,
  "",
  printf "[![Hackage](%s)](%s)" hackageShield hackageLink,
  printf "[![Build status](%s)](%s)" travisShield travisLink,
  printf "[![%s license](%s)](%s)" license licenseShield licenseLink ]
  where
    hackageShield :: String =
      printf "https://img.shields.io/hackage/v/%s.svg" repo
    hackageLink :: String =
      printf "https://hackage.haskell.org/package/%s" repo
    travisShield :: String =
      printf "https://secure.travis-ci.org/%s/%s.svg" owner repo
    travisLink :: String =
      printf "https://travis-ci.org/%s/%s" owner repo
    licenseShield :: String =
      printf "https://img.shields.io/badge/license-%s-blue.svg" (replace "-" "--" license)
    licenseLink :: String =
      printf "https://github.com/%s/%s/blob/master/LICENSE" owner repo

emptyModule :: String -> String
emptyModule name = unlines [
  "module " ++ name,
  "(",
  ")",
  "where" ]

mainModule :: String
mainModule = unlines [
  "module Main (main) where",
  "",
  "main :: IO ()",
  "main = return ()" ]

publicDomainLicense :: String
publicDomainLicense = unlines [
  "Creative Commons Legal Code",
  "",
  "CC0 1.0 Universal",
  "",
  "    CREATIVE COMMONS CORPORATION IS NOT A LAW FIRM AND DOES NOT PROVIDE",
  "    LEGAL SERVICES. DISTRIBUTION OF THIS DOCUMENT DOES NOT CREATE AN",
  "    ATTORNEY-CLIENT RELATIONSHIP. CREATIVE COMMONS PROVIDES THIS",
  "    INFORMATION ON AN \"AS-IS\" BASIS. CREATIVE COMMONS MAKES NO WARRANTIES",
  "    REGARDING THE USE OF THIS DOCUMENT OR THE INFORMATION OR WORKS",
  "    PROVIDED HEREUNDER, AND DISCLAIMS LIABILITY FOR DAMAGES RESULTING FROM",
  "    THE USE OF THIS DOCUMENT OR THE INFORMATION OR WORKS PROVIDED",
  "    HEREUNDER.",
  "",
  "Statement of Purpose",
  "",
  "The laws of most jurisdictions throughout the world automatically confer",
  "exclusive Copyright and Related Rights (defined below) upon the creator",
  "and subsequent owner(s) (each and all, an \"owner\") of an original work of",
  "authorship and/or a database (each, a \"Work\").",
  "",
  "Certain owners wish to permanently relinquish those rights to a Work for",
  "the purpose of contributing to a commons of creative, cultural and",
  "scientific works (\"Commons\") that the public can reliably and without fear",
  "of later claims of infringement build upon, modify, incorporate in other",
  "works, reuse and redistribute as freely as possible in any form whatsoever",
  "and for any purposes, including without limitation commercial purposes.",
  "These owners may contribute to the Commons to promote the ideal of a free",
  "culture and the further production of creative, cultural and scientific",
  "works, or to gain reputation or greater distribution for their Work in",
  "part through the use and efforts of others.",
  "",
  "For these and/or other purposes and motivations, and without any",
  "expectation of additional consideration or compensation, the person",
  "associating CC0 with a Work (the \"Affirmer\"), to the extent that he or she",
  "is an owner of Copyright and Related Rights in the Work, voluntarily",
  "elects to apply CC0 to the Work and publicly distribute the Work under its",
  "terms, with knowledge of his or her Copyright and Related Rights in the",
  "Work and the meaning and intended legal effect of CC0 on those rights.",
  "",
  "1. Copyright and Related Rights. A Work made available under CC0 may be",
  "protected by copyright and related or neighboring rights (\"Copyright and",
  "Related Rights\"). Copyright and Related Rights include, but are not",
  "limited to, the following:",
  "",
  "  i. the right to reproduce, adapt, distribute, perform, display,",
  "     communicate, and translate a Work;",
  " ii. moral rights retained by the original author(s) and/or performer(s);",
  "iii. publicity and privacy rights pertaining to a person's image or",
  "     likeness depicted in a Work;",
  " iv. rights protecting against unfair competition in regards to a Work,",
  "     subject to the limitations in paragraph 4(a), below;",
  "  v. rights protecting the extraction, dissemination, use and reuse of data",
  "     in a Work;",
  " vi. database rights (such as those arising under Directive 96/9/EC of the",
  "     European Parliament and of the Council of 11 March 1996 on the legal",
  "     protection of databases, and under any national implementation",
  "     thereof, including any amended or successor version of such",
  "     directive); and",
  "vii. other similar, equivalent or corresponding rights throughout the",
  "     world based on applicable law or treaty, and any national",
  "     implementations thereof.",
  "",
  "2. Waiver. To the greatest extent permitted by, but not in contravention",
  "of, applicable law, Affirmer hereby overtly, fully, permanently,",
  "irrevocably and unconditionally waives, abandons, and surrenders all of",
  "Affirmer's Copyright and Related Rights and associated claims and causes",
  "of action, whether now known or unknown (including existing as well as",
  "future claims and causes of action), in the Work (i) in all territories",
  "worldwide, (ii) for the maximum duration provided by applicable law or",
  "treaty (including future time extensions), (iii) in any current or future",
  "medium and for any number of copies, and (iv) for any purpose whatsoever,",
  "including without limitation commercial, advertising or promotional",
  "purposes (the \"Waiver\"). Affirmer makes the Waiver for the benefit of each",
  "member of the public at large and to the detriment of Affirmer's heirs and",
  "successors, fully intending that such Waiver shall not be subject to",
  "revocation, rescission, cancellation, termination, or any other legal or",
  "equitable action to disrupt the quiet enjoyment of the Work by the public",
  "as contemplated by Affirmer's express Statement of Purpose.",
  "",
  "3. Public License Fallback. Should any part of the Waiver for any reason",
  "be judged legally invalid or ineffective under applicable law, then the",
  "Waiver shall be preserved to the maximum extent permitted taking into",
  "account Affirmer's express Statement of Purpose. In addition, to the",
  "extent the Waiver is so judged Affirmer hereby grants to each affected",
  "person a royalty-free, non transferable, non sublicensable, non exclusive,",
  "irrevocable and unconditional license to exercise Affirmer's Copyright and",
  "Related Rights in the Work (i) in all territories worldwide, (ii) for the",
  "maximum duration provided by applicable law or treaty (including future",
  "time extensions), (iii) in any current or future medium and for any number",
  "of copies, and (iv) for any purpose whatsoever, including without",
  "limitation commercial, advertising or promotional purposes (the",
  "\"License\"). The License shall be deemed effective as of the date CC0 was",
  "applied by Affirmer to the Work. Should any part of the License for any",
  "reason be judged legally invalid or ineffective under applicable law, such",
  "partial invalidity or ineffectiveness shall not invalidate the remainder",
  "of the License, and in such case Affirmer hereby affirms that he or she",
  "will not (i) exercise any of his or her remaining Copyright and Related",
  "Rights in the Work or (ii) assert any associated claims and causes of",
  "action with respect to the Work, in either case contrary to Affirmer's",
  "express Statement of Purpose.",
  "",
  "4. Limitations and Disclaimers.",
  "",
  " a. No trademark or patent rights held by Affirmer are waived, abandoned,",
  "    surrendered, licensed or otherwise affected by this document.",
  " b. Affirmer offers the Work as-is and makes no representations or",
  "    warranties of any kind concerning the Work, express, implied,",
  "    statutory or otherwise, including without limitation warranties of",
  "    title, merchantability, fitness for a particular purpose, non",
  "    infringement, or the absence of latent or other defects, accuracy, or",
  "    the present or absence of errors, whether or not discoverable, all to",
  "    the greatest extent permissible under applicable law.",
  " c. Affirmer disclaims responsibility for clearing rights of other persons",
  "    that may apply to the Work or any use thereof, including without",
  "    limitation any person's Copyright and Related Rights in the Work.",
  "    Further, Affirmer disclaims responsibility for obtaining any necessary",
  "    consents, permissions or other rights required for any use of the",
  "    Work.",
  " d. Affirmer understands and acknowledges that Creative Commons is not a",
  "    party to this document and has no duty or obligation with respect to",
  "    this CC0 or use of the Work." ]
