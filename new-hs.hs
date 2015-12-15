#!/usr/bin/env runghc


{-# LANGUAGE
OverloadedStrings,
FlexibleInstances,
TypeFamilies,
MultiWayIf
  #-}


import Control.Exception
import Control.Monad
import Control.Monad.State
import Data.Functor
import Data.List
import Data.String
import System.Directory
import System.Process
import Text.Printf


instance (a ~ String, b ~ ()) => IsString ([a] -> IO b) where
  fromString "cd" [arg] = setCurrentDirectory arg
  fromString cmd args = callCommand $ showCommandForUser cmd args

printQuestion :: String -> [String] -> IO ()
printQuestion question (def:rest) =
  printf "%s [%s]/%s " question def (intercalate "/" rest)

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

(~==), (=~=), (==~) :: String -> String -> Bool
(~==) = isPrefixOf
(=~=) = isInfixOf
(==~) = isSuffixOf

splitOn :: String -> String -> [String]
splitOn _ "" = []
splitOn x s = go "" s
  where
    go b s
      | null s && null b = [""]
      | null s           = [reverse b]
      | x ~== s          = reverse b : go "" (drop (length x) s)
      | otherwise        = go (head s : b) (tail s)

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

main :: IO ()
main = do
  -- Create a repository.
  owner <- queryDef "Owner?" "aelve"
  repo <- query "Repo?"
  "mkdir" [repo]
  "cd" [repo]
  "git" ["init"]

  -- Create the repository on Github.
  description <- query "Description?"
  "hub" ["create", "-d", description, printf "%s/%s" owner repo]

  -- Create a .gitignore.
  writeFile ".gitignore" gitignore

  -- Create a changelog.
  writeFile "CHANGELOG.md" changelog

  -- Generate Cabal project.
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
  license <- choose "License?" (words "BSD3 BSD2 GPL-3 GPL-2 MIT PublicDomain")
  when (license == "PublicDomain") $
    writeFile "LICENSE" publicDomainLicense
  (isLib, isExe) <- ask "Library or executable?" [
    "lib"  ==> return (True, False),
    "exe"  ==> return (False, True),
    "both" ==> return (True, True) ]
  someModule <- query "Some module name?"
  "cabal" [
    "init",
    "--non-interactive",
    "--no-comments",
    "--synopsis", description,
    "--homepage", printf "http://github.com/%s/%s" owner repo,
    "--category", category,
    "--license", license,
    if isLib then "--is-library" else "--is-executable",
    "--extra-source-file", "CHANGELOG.md",
    "--source-dir", if isLib then "lib" else "src",
    "--expose-module", someModule ]

  -- Edit the .cabal file.
  let cabalName = printf "%s.cabal" repo
  cabalFile <- readFile' cabalName
  testedVersions <- words <$>
    queryDef "Versions of GHC to test with?" "7.8.4 7.10.3"
  longDescription <-
    (\s -> if s == "repo description" then description else s) <$>
    queryDef "Longer description?" "repo description"
  writeFile cabalName $ flip execState cabalFile $ do
    -- Remove the “generated with cabal” comment.
    modify $ unparagraphs . tail . paragraphs
    -- Add a source-repository section.
    let sourceRepo = unlines [
          "source-repository head",
          "  type:                git",
          printf "  location:            git://github.com/%s/%s.git"
            owner repo ]
    modify $ unparagraphs . (\(p:ps) -> (p:sourceRepo:ps)) . paragraphs
    -- Add a bug-reports field.
    let bugReports =
          printf "bug-reports:         http://github.com/%s/%s/issues"
            owner repo
    modify $ \s -> do
      let (p:ps) = paragraphs s
      let (l, x:r) = break ("homepage" ~==) (lines p)
      unparagraphs (unlines (l ++ [x, bugReports] ++ r) : ps)
    -- Add a tested-with field.
    let testedWith = "tested-with:         " ++
          intercalate ", " (map ("GHC == " ++) testedVersions)
    modify $ \s -> do
      let (p:ps) = paragraphs s
      let (l, x:r) = break ("category" ~==) (lines p)
      unparagraphs (unlines (l ++ [x, testedWith] ++ r) : ps)
    -- Add a longer description.
    let desc1 = "description:"
        desc2 = "  " ++ longDescription
    modify $ \s -> do
      let (p:ps) = paragraphs s
      let (l, _:r) = break ("-- description" ~==) (lines p)
      unparagraphs (unlines (l ++ [desc1, desc2] ++ r) : ps)
    -- Enable warnings.
    let ghcOptions = "  ghc-options:         -Wall -fno-warn-unused-do-bind"
    modify $ unparagraphs
           . map (\p ->
               if "hs-source-dirs" =~= p
                 then let (l, x:r) = break ("  hs-source-dirs" ~==) (lines p)
                      in  unlines (l ++ [ghcOptions, x] ++ r)
                 else p)
           . paragraphs
  "cabal" ["check"]

  -- Create Cabal sandbox.
  ask "Create Cabal sandbox?" [
    "n" ==> return (),
    "y" ==> "cabal" ["sandbox", "init"] ]

  -- Create a .travis.yml file and enable Travis.
  "travis" ["enable"]
  let travisName = ".travis.yml"
  "wget" ["https://raw.githubusercontent.com/hvr/multi-ghc-travis\
          \/master/make_travis_yml.hs"]
  "chmod" ["+x", "make_travis_yml.hs"]
  callCommand (printf "./make_travis_yml.hs %s > %s" cabalName travisName)
  "rm" ["make_travis_yml.hs"]

  -- Edit the .travis.yml file.
  travisFile <- readFile' travisName
  writeFile travisName $ flip execState travisFile $ do
    -- Don't tolerate warnings.
    let werror = "- cabal build --ghc-options=-Werror"
    modify $ unparagraphs
           . map (\p -> if "script:" =~= p
                          then replace "- cabal build" werror p
                          else p)
           . paragraphs

  -- Create a module.
  when isLib $ do
    let moduleName = last (splitOn "." someModule)
        moduleDir  = intercalate "/" ("lib" : init (splitOn "." someModule))
    "mkdir" ["-p", moduleDir]
    writeFile (printf "%s/%s.hs" moduleDir moduleName) (emptyModule someModule)

  -- Make a commit.
  "git" ["add", "."]
  "git" ["commit", "-m", "Initial commit"]

{-

Table of contents:

  * gitignore
  * changelog
  * emptyModule
  * publicDomainLicense

-}

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

changelog = unlines [
  "# 0.1.0.0",
  "",
  "First release."]

emptyModule name = unlines [
  "module " ++ name,
  "(",
  ")",
  "where" ]

publicDomainLicense = unlines [
  "     CREATIVE COMMONS CORPORATION IS NOT A LAW FIRM AND DOES NOT",
  "     PROVIDE LEGAL SERVICES. DISTRIBUTION OF THIS DOCUMENT DOES NOT",
  "     CREATE AN ATTORNEY-CLIENT RELATIONSHIP. CREATIVE COMMONS PROVIDES",
  "     THIS INFORMATION ON AN \"AS-IS\" BASIS. CREATIVE COMMONS MAKES NO",
  "     WARRANTIES REGARDING THE USE OF THIS DOCUMENT OR THE INFORMATION",
  "     OR WORKS PROVIDED HEREUNDER, AND DISCLAIMS LIABILITY FOR DAMAGES",
  "     RESULTING FROM THE USE OF THIS DOCUMENT OR THE INFORMATION OR",
  "     WORKS PROVIDED HEREUNDER.",
  "",
  "Statement of Purpose",
  "",
  "The laws of most jurisdictions throughout the world automatically",
  "confer exclusive Copyright and Related Rights (defined below) upon the",
  "creator and subsequent owner(s) (each and all, an \"owner\") of an",
  "original work of authorship and/or a database (each, a \"Work\").",
  "",
  "Certain owners wish to permanently relinquish those rights to a Work",
  "for the purpose of contributing to a commons of creative, cultural and",
  "scientific works (\"Commons\") that the public can reliably and without",
  "fear of later claims of infringement build upon, modify, incorporate",
  "in other works, reuse and redistribute as freely as possible in any",
  "form whatsoever and for any purposes, including without limitation",
  "commercial purposes. These owners may contribute to the Commons to",
  "promote the ideal of a free culture and the further production of",
  "creative, cultural and scientific works, or to gain reputation or",
  "greater distribution for their Work in part through the use and",
  "efforts of others.",
  "",
  "For these and/or other purposes and motivations, and without any",
  "expectation of additional consideration or compensation, the person",
  "associating CC0 with a Work (the \"Affirmer\"), to the extent that he or",
  "she is an owner of Copyright and Related Rights in the Work,",
  "voluntarily elects to apply CC0 to the Work and publicly distribute",
  "the Work under its terms, with knowledge of his or her Copyright and",
  "Related Rights in the Work and the meaning and intended legal effect",
  "of CC0 on those rights.",
  "",
  "1. Copyright and Related Rights. A Work made available under CC0 may",
  "be protected by copyright and related or neighboring rights",
  "(\"Copyright and Related Rights\"). Copyright and Related Rights",
  "include, but are not limited to, the following:",
  "",
  "    the right to reproduce, adapt, distribute, perform, display,",
  "    communicate, and translate a Work; moral rights retained by the",
  "    original author(s) and/or performer(s); publicity and privacy",
  "    rights pertaining to a person's image or likeness depicted in a",
  "    Work; rights protecting against unfair competition in regards to a",
  "    Work, subject to the limitations in paragraph 4(a), below; rights",
  "    protecting the extraction, dissemination, use and reuse of data in",
  "    a Work; database rights (such as those arising under Directive",
  "    96/9/EC of the European Parliament and of the Council of 11 March",
  "    1996 on the legal protection of databases, and under any national",
  "    implementation thereof, including any amended or successor version",
  "    of such directive); and other similar, equivalent or corresponding",
  "    rights throughout the world based on applicable law or treaty, and",
  "    any national implementations thereof.",
  "",
  "2. Waiver. To the greatest extent permitted by, but not in",
  "contravention of, applicable law, Affirmer hereby overtly, fully,",
  "permanently, irrevocably and unconditionally waives, abandons, and",
  "surrenders all of Affirmer's Copyright and Related Rights and",
  "associated claims and causes of action, whether now known or unknown",
  "(including existing as well as future claims and causes of action), in",
  "the Work (i) in all territories worldwide, (ii) for the maximum",
  "duration provided by applicable law or treaty (including future time",
  "extensions), (iii) in any current or future medium and for any number",
  "of copies, and (iv) for any purpose whatsoever, including without",
  "limitation commercial, advertising or promotional purposes (the",
  "\"Waiver\"). Affirmer makes the Waiver for the benefit of each member of",
  "the public at large and to the detriment of Affirmer's heirs and",
  "successors, fully intending that such Waiver shall not be subject to",
  "revocation, rescission, cancellation, termination, or any other legal",
  "or equitable action to disrupt the quiet enjoyment of the Work by the",
  "public as contemplated by Affirmer's express Statement of Purpose.",
  "",
  "3. Public License Fallback. Should any part of the Waiver for any",
  "reason be judged legally invalid or ineffective under applicable law,",
  "then the Waiver shall be preserved to the maximum extent permitted",
  "taking into account Affirmer's express Statement of Purpose. In",
  "addition, to the extent the Waiver is so judged Affirmer hereby grants",
  "to each affected person a royalty-free, non transferable, non",
  "sublicensable, non exclusive, irrevocable and unconditional license to",
  "exercise Affirmer's Copyright and Related Rights in the Work (i) in",
  "all territories worldwide, (ii) for the maximum duration provided by",
  "applicable law or treaty (including future time extensions), (iii) in",
  "any current or future medium and for any number of copies, and (iv)",
  "for any purpose whatsoever, including without limitation commercial,",
  "advertising or promotional purposes (the \"License\"). The License shall",
  "be deemed effective as of the date CC0 was applied by Affirmer to the",
  "Work. Should any part of the License for any reason be judged legally",
  "invalid or ineffective under applicable law, such partial invalidity",
  "or ineffectiveness shall not invalidate the remainder of the License,",
  "and in such case Affirmer hereby affirms that he or she will not (i)",
  "exercise any of his or her remaining Copyright and Related Rights in",
  "the Work or (ii) assert any associated claims and causes of action",
  "with respect to the Work, in either case contrary to Affirmer's",
  "express Statement of Purpose.",
  "",
  "4. Limitations and Disclaimers.",
  "",
  "    No trademark or patent rights held by Affirmer are waived,",
  "    abandoned, surrendered, licensed or otherwise affected by this",
  "    document.  Affirmer offers the Work as-is and makes no",
  "    representations or warranties of any kind concerning the Work,",
  "    express, implied, statutory or otherwise, including without",
  "    limitation warranties of title, merchantability, fitness for a",
  "    particular purpose, non infringement, or the absence of latent or",
  "    other defects, accuracy, or the present or absence of errors,",
  "    whether or not discoverable, all to the greatest extent",
  "    permissible under applicable law.  Affirmer disclaims",
  "    responsibility for clearing rights of other persons that may apply",
  "    to the Work or any use thereof, including without limitation any",
  "    person's Copyright and Related Rights in the Work. Further,",
  "    Affirmer disclaims responsibility for obtaining any necessary",
  "    consents, permissions or other rights required for any use of the",
  "    Work.  Affirmer understands and acknowledges that Creative Commons",
  "    is not a party to this document and has no duty or obligation with",
  "    respect to this CC0 or use of the Work." ]
