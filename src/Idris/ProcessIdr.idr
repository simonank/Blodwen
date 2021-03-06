module Idris.ProcessIdr

import Core.Binary
import Core.Context
import Core.Directory
import Core.Metadata
import Core.Options
import Core.Unify

import TTImp.ProcessTTImp
import TTImp.Reflect
import TTImp.TTImp

import Idris.Parser
import Idris.Syntax
import Idris.Desugar

import Control.Catchable
import Interfaces.FileIO

processDecl : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST (UState FC)} ->
              {auto i : Ref ImpST (ImpState FC)} ->
              {auto s : Ref Syn SyntaxInfo} ->
              {auto m : Ref Meta (Metadata FC)} ->
              PDecl -> Core FC (Maybe (Error FC))
processDecl decl
    = catch (do impdecls <- desugarDecl [] decl 
                traverse (ProcessTTImp.processDecl False [] (MkNested [])) impdecls
                pure Nothing)
            (\err => do giveUpSearch -- or we'll keep trying...
                        pure (Just err))

processDecls : {auto c : Ref Ctxt Defs} ->
               {auto u : Ref UST (UState FC)} ->
               {auto i : Ref ImpST (ImpState FC)} ->
               {auto s : Ref Syn SyntaxInfo} ->
               {auto m : Ref Meta (Metadata FC)} ->
               List PDecl -> Core FC (List (Error FC))
processDecls decls
    = do xs <- traverse processDecl decls
         Nothing <- checkDelayedHoles 
             | Just err => pure (mapMaybe id xs ++ [err])
         hs <- getHoleNames
         traverse addToSave hs
         pure (mapMaybe id xs)

readModule : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST (UState FC)} ->
             {auto s : Ref Syn SyntaxInfo} ->
             FC ->
             (visible : Bool) -> -- Is import visible to top level module?
             (reexp : Bool) -> -- Should the module be reexported?
             (imp : List String) -> -- Module name to import
             (as : List String) -> -- Namespace to import into
             Core FC ()
readModule loc vis reexp imp as
    = do fname <- nsToPath loc imp
         Just (syn, more) <- readFromTTC {extra = SyntaxInfo} loc vis fname imp as
              | Nothing => when vis (setVisible imp) -- already loaded, just set visibility
         addImported (imp, reexp, as)
         extendAs imp as syn
         modNS <- getNS
         when vis $ setVisible imp
         traverse (\ mimp => 
                       do let m = fst mimp
                          let reexp = fst (snd mimp)
                          let as = snd (snd mimp)
                          readModule loc (vis && reexp) reexp m as) more
         setNS modNS

readImport : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST (UState FC)} ->
             {auto s : Ref Syn SyntaxInfo} ->
             Import -> Core FC ()
readImport imp
    = readModule (loc imp) True (reexport imp) (path imp) (nameAs imp)

prelude : Import
prelude = MkImport (MkFC "(implicit)" (0, 0) (0, 0)) False
                     ["Prelude"] ["Prelude"]

export
readPrelude : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST (UState FC)} ->
              {auto s : Ref Syn SyntaxInfo} ->
              Core FC ()
readPrelude = do readImport prelude 
                 setNS ["Main"]

-- Import a TTC for use as the main file (e.g. at the REPL)
export
readAsMain : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST (UState FC)} ->
             {auto s : Ref Syn SyntaxInfo} ->
             (fname : String) -> Core FC ()
readAsMain fname
    = do Just (syn, more) <- readFromTTC {extra = SyntaxInfo} 
                                         toplevelFC True fname [] []
              | Nothing => pure ()
         replNS <- getNS
         extendAs replNS replNS syn
         traverse (\ mimp => 
                       do let m = fst mimp
                          let as = snd (snd mimp)
                          fname <- nsToPath emptyFC m
                          readModule emptyFC True False m as) more
         setNS replNS

addPrelude : List Import -> List Import
addPrelude imps 
  = if not (["Prelude"] `elem` map path imps)
       then prelude :: imps
       else imps

-- Process everything in the module; return the syntax information which
-- needs to be written to the TTC (e.g. exported infix operators)
processMod : {auto c : Ref Ctxt Defs} ->
             {auto u : Ref UST (UState FC)} ->
             {auto s : Ref Syn SyntaxInfo} ->
             {auto m : Ref Meta (Metadata FC)} ->
             Module -> Core FC (List (Error FC))
processMod mod
    = catch (do i <- newRef ImpST (initImpState {annot = FC})
                let ns = moduleNS mod
                when (ns /= ["Main"]) $
                   do let MkFC fname _ _ = headerloc mod
                      d <- getDirs
                      when (pathToNS (working_dir d) fname /= ns) $
                          throw (GenericMsg (headerloc mod) 
                                   ("Module name " ++ showSep "." (reverse ns) ++
                                    " does not match file name " ++ fname))
                -- Add an implicit prelude import
                let imps =
                     if (noprelude !getSession || moduleNS mod == ["Prelude"])
                        then imports mod
                        else addPrelude (imports mod)
                -- read imports here
                -- Note: We should only import .ttc - assumption is that there's
                -- a phase before this which builds the dependency graph
                -- (also that we only build child dependencies if rebuilding
                -- changes the interface - will need to store a hash in .ttc!)
                traverse readImport imps
                -- Before we process the source, make sure the "hide_everywhere"
                -- names are set to private
                defs <- get Ctxt
                traverse (\x => setVisibility emptyFC x Private) (hiddenNames defs)
                setNS ns
                processDecls (decls mod))
            (\err => pure [err])

-- Process a file. Returns any errors, rather than throwing them, because there
-- might be lots of errors collected across a whole file.
export
process : {auto c : Ref Ctxt Defs} ->
          {auto u : Ref UST (UState FC)} ->
          {auto s : Ref Syn SyntaxInfo} ->
          {auto m : Ref Meta (Metadata FC)} ->
          FileName -> Core FC (List (Error FC))
process file
    = do Right res <- coreLift (readFile file)
               | Left err => pure [FileErr file err]
         case runParser res (do p <- prog file; eoi; pure p) of
              Left err => pure [ParseFail err]
              Right mod =>
                -- Processing returns a list of errors across a whole module,
                -- but may fail for other reasons, so we still need to catch
                -- other possible errors
                    catch (do errs <- processMod mod
                              if isNil errs
                                 then
                                   do defs <- get Ctxt
                                      d <- getDirs
                                      makeBuildDirectory (pathToNS (working_dir d) file)
                                      fn <- getTTCFileName file ".ttc"
                                      writeToTTC !(get Syn) fn
                                      mfn <- getTTCFileName file ".ttm"
                                      writeToTTM mfn
                                      pure []
                                 else pure errs)
                          (\err => pure [err])
