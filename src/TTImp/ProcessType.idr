module TTImp.ProcessType

import Core.TT
import Core.Unify
import Core.Context

import TTImp.Elab
import TTImp.TTImp

import Control.Catchable

export
processType : {auto c : Ref Ctxt Defs} ->
              {auto u : Ref UST (UState annot)} ->
              {auto i : Ref ImpST (ImpState annot)} ->
              Elaborator annot ->
              Env Term vars ->
              ImpTy annot -> 
              Core annot ()
processType elab env (MkImpTy annot n ty_raw)
    = do ty_imp <- mkBindImps ty_raw
         ty <- checkTerm elab env (PI False) InType ty_imp TType
         log 1 $ show n ++ " : " ++ show ty
         addDef n (newDef (abstractEnvType env ty) Public None)

