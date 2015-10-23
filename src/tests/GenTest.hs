{-# OPTIONS_GHC -F -pgmF htfpp #-}
{-# LANGUAGE OverloadedStrings #-}

module GenTest (htf_thisModulesTests) where

import Control.Monad (forM)
import Control.Exception (try)
import GHC.Exception (ErrorCall(..))
import Data.Monoid ((<>))
import Data.Text (Text)
import Test.Framework
import qualified Sneak.AST as AST
import qualified Sneak.Lex
import qualified Sneak.Parse
import qualified Sneak.Module
import qualified Sneak.Typecheck as Typecheck
import qualified Sneak.Gen as Gen
import qualified Sneak.Backend.JS as JS

genDoc' :: Text -> IO (Either String Gen.Module)
genDoc' src = do
    let fn = "<string>"
    mod' <- Sneak.Module.loadModuleFromSource "<string>" src
    case mod' of
        Left err ->
            return $ Left err
        Right m -> do
            fmap Right $ Gen.generateModule m

genDoc :: Text -> IO Gen.Module
genDoc src = do
    rv <- genDoc' src
    case rv of
        Left err -> error err
        Right stmts -> return stmts

case_direct_prints = do
    doc <- genDoc "let _ = print(10);"
    assertEqual
        [ Gen.Declaration AST.NoExport $ Gen.DLet "_"
            [ Gen.Intrinsic (Gen.Temporary 0) $ AST.IPrint [Gen.Literal $ AST.LInteger 10]
            , Gen.Return $ Gen.Reference (Gen.Temporary 0)
            ]
        ]
        doc

case_return_at_top_level_is_error = do
    result <- try $! genDoc "let _ = return 1;"
    assertEqual (Left $ ErrorCall "Cannot return outside of functions") $ result

case_return_from_function = do
    doc <- genDoc "fun f() { return 1; }"
    assertEqual
        [ Gen.Declaration AST.NoExport $ Gen.DFun "f" [] $
            [ Gen.Return $ Gen.Literal $ AST.LInteger 1
            ]
        ]
        doc

case_return_from_branch = do
    result <- genDoc "fun f() { if True then return 1 else return 2; }"
    assertEqual
        [ Gen.Declaration AST.NoExport $ Gen.DFun "f" []
            [ Gen.EmptyLet $ Gen.Temporary 0
            , Gen.If (Gen.Reference $ Gen.Binding $ AST.OtherModule "Prelude" "True")
                [ Gen.Return $ Gen.Literal $ AST.LInteger 1
                ]
                [ Gen.Return $ Gen.Literal $ AST.LInteger 2
                ]
            , Gen.Return $ Gen.Reference $ Gen.Temporary 0
            ]
        ]
        result

case_branch_with_value = do
    result <- genDoc "let x = if True then 1 else 2;"
    assertEqual
        [ Gen.Declaration AST.NoExport $ Gen.DLet "x"
            [ Gen.EmptyLet (Gen.Temporary 0)
            , Gen.If (Gen.Reference $ Gen.Binding $ AST.OtherModule "Prelude" "True")
                [ Gen.Assign (Gen.Temporary 0) $ Gen.Literal $ AST.LInteger 1
                ]
                [ Gen.Assign (Gen.Temporary 0) $ Gen.Literal $ AST.LInteger 2
                ]
            , Gen.Return $ Gen.Reference $ Gen.Temporary 0
            ]
        ]
        result

case_method_call = do
    result <- genDoc "let hoop = _unsafe_js(\"we-can-put-anything-here\"); let _ = hoop.woop();"
    assertEqual
        [ Gen.Declaration AST.NoExport (Gen.DLet "hoop" [Gen.Intrinsic (Gen.Temporary 0) (AST.IUnsafeJs "we-can-put-anything-here")
        , Gen.Return (Gen.Reference (Gen.Temporary 0))])
        , Gen.Declaration AST.NoExport (Gen.DLet "_" [Gen.MethodCall (Gen.Temporary 1) (Gen.Reference (Gen.Binding $ AST.ThisModule "hoop")) "woop" []
            , Gen.Return (Gen.Reference (Gen.Temporary 1))])
        ]
        result
