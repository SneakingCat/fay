-- | Dealing with Cabal packages in Fay's own special way.

module Language.Fay.Compiler.Packages where

import Language.Fay.Types

import Control.Monad
import Data.List
import GHC.Paths
import System.Directory
import System.FilePath
import System.Process.Extra

-- | Given a configuration, resolve any packages specified to their
-- data file directories for importing the *.hs sources.
resolvePackages :: CompileConfig -> IO CompileConfig
resolvePackages config = do
  foldM resolvePackage config (configPackages config)

-- | Resolve package.
resolvePackage :: CompileConfig -> String -> IO CompileConfig
resolvePackage config name = do
  desc <- describePackage (configPackageConf config) name
  dirs <- shareDirs desc
  case dirs of
    Nothing -> error $ "unable to find share dir of package: " ++ name
    Just ds -> do
      mapM_ checkDirExists ds
      return (addConfigDirectoryIncludes ds config)

-- | Describe package with ghc-pkg.
--
--   Weinsworth : Why are you not using the GHC API which would
--                provide you this information like in modules like
--                Packages which has functions like
--
--                collectIncludeDirs :: [PackageConfig] -> [FilePath]
--
--                and awesome stuff like that. What are you, stupid?
--
--   Batemen : Pretty much. I think this might be a little faster than
--             initializing GHC, and using the GHC API adds a lot of
--             link time when you use it.
--
--   Weinsworth : Uh huh.
--
--   Batemen: Yeah. Stop looking at me like that.
--
describePackage :: Maybe FilePath -> String -> IO String
describePackage db name = do
  result <- readAllFromProcess ghc_pkg args ""
  case result of
    Left err -> error $ "ghc-pkg describe error:\n" ++ err
    Right (_err,out) -> return out

  where args = concat [["describe",name]
                      ,["-f" ++ db' | Just db' <- [db]]]

-- | Get the share dirs of the package.
--
--   Alright.
--   Stop.
--   Collaborate and listen.
--
--   You're gonna have to stop scrolling and read this.
--
--   I can't figure out how to get the data-dirs from the package
--   description.
--
--   * It doesn't seem to be in the Cabal API's PackageDescription type.
--   * It doesn't seem to be in the ghc-pkg description.
--   * I can't find out how to read the Cabal configuration. Yeah, I
--     could probably find it eventually. Shut up.
--
--   So what I'm doing is parsing the “import-dirs” flag, which
--   appears in ghc-pkg's output like this:
--
--   /home/chris/Projects/me/fay-jquery/cabal-dev//lib/fay-jquery-0.1.0.0/ghc-7.4.1
--
--   And I'm going to replace “lib” with “share” and drop the “ghc-*”
--   and that, under a *normal* configuration, gives the share
--   directory.
--
--   Under an atypical situation, we're going to throw an error and
--   you guys will just have to submit a pull request or some code to
--   do this better, because I've got better things to be doing, like
--   climbing trees, baking cookies and reading books about zombies.
--
shareDirs :: String -> IO (Maybe [FilePath])
shareDirs desc =
  case find (isPrefixOf "import-dirs: ") (lines desc) of
    Nothing -> return Nothing
    Just idirs ->
      case words idirs of
        -- I'm going to take the first one. If you've got more, just,
        -- I hate you.
        (_import_dirs:idir:_) -> do
          exists1 <- doesFileExist $ munge swap1 idir
          -- First we try to get the normal path which looks something like share/pkgid
          -- But HP on OS X defaults to /lib/pkgid/share so lets try that too.
          -- If your cabal config is even crazier, you need to patch fay to read the config or something.
          return $ if exists1
            then Just [munge swap1 idir, munge swap1 idir </> "src"]
            else Just [munge swap2 idir, munge swap2 idir </> "src"]
        _ -> return Nothing

  where
    munge f = joinPath . reverse . f . dropGhc . reverse . map dropTrailingPathSeparator . splitPath
    dropGhc = drop 1
    swap1 (name_version:"lib":rest) = name_version : "share" : rest
    swap1 paths = err paths
    swap2 (name_version:"lib":rest) = "share" : name_version : "lib" : rest
    swap2 paths = err paths
    err paths = error $ "unable to complete munging of the lib dir\
                         \, see Language.Fay.Compiler.Packages.hs \
                         \for an explanation: " ++
                           "\npath was: " ++ joinPath paths

-- | Might as well check the dir that we munged to death actually
--   exists. -___ -
checkDirExists :: FilePath -> IO ()
checkDirExists p = do
  don'tFlipOut <- doesDirectoryExist p
  unless don'tFlipOut $
    error $ "so the directory we munged doesn't exist:\n  " ++ p ++
            "\nreport a bug, we screwed up."
