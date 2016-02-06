{-# OPTIONS_GHC -F -pgmF htfpp #-}
{-# LANGUAGE OverloadedStrings #-}

module ParseTest (htf_thisModulesTests) where

import           Crux.Parse
import           Crux.AST
import qualified Crux.Lex as Lex
import qualified Data.Text as T
import           Test.Framework
import qualified Text.Parsec as P
import Data.HashMap.Strict (fromList)

discardData expr = fmap (const ()) expr

runParse :: Parser a -> T.Text -> IO (Either P.ParseError a)
runParse parser source =
    case Lex.lexSource "<>" source of
        Left err ->
            assertFailure $ "Lexer error: " ++ show err
        Right tokens ->
            return $ runParser parser "hs.ParseTest" "<>" tokens


-- assertParseOk :: (Show a, Eq a) => Parser (Expression a) -> T.Text -> (Expression a) -> IO ()
assertParseOk parser source expected f = do
    case Lex.lexSource "<>" source of
        Left err ->
            assertFailure $ "Lexer error: " ++ show err
        Right tokens -> do
            let res = runParser parser "hs.ParseTest" "<>" tokens
            case res of
                Right result -> assertEqualVerbose (T.unpack source) expected (f result)
                Left err -> assertFailure ("Parse failed: " ++ show err)

assertExprParses parser source expected = assertParseOk parser source expected discardData

test_literals = do
    assertExprParses literalExpression "5"
        (ELiteral () (LInteger 5))
    assertExprParses literalExpression "\"Hooper\""
        (ELiteral () (LString "Hooper"))
    assertExprParses literalExpression "()"
        (ELiteral () (LUnit))
    assertExprParses literalExpression "[]"
        (EArrayLiteral () [])
    assertExprParses literalExpression "[(), 1, \"hi\"]"
        (EArrayLiteral () [ELiteral () LUnit, ELiteral () $ LInteger 1, ELiteral () $ LString "hi"])

test_parens = do
    assertExprParses noSemiExpression "(5)"
        (ELiteral () (LInteger 5))

test_application = do
    assertExprParses noSemiExpression "foo()"
        (EApp () (EIdentifier () "foo") [])

test_application_with_args = do
    assertExprParses noSemiExpression "foo(bar, baz)"
        (EApp () (EIdentifier () "foo") [EIdentifier () "bar", EIdentifier () "baz"])

test_application_association = do
    assertExprParses noSemiExpression "1 + length(list)"
        (EBinIntrinsic () BIPlus (ELiteral () (LInteger 1)) (EApp () (EIdentifier () "length") [EIdentifier () "list"]))

test_let = do
    assertExprParses letExpression "let a = \"Hello\""
        (ELet () LImmutable (PBinding "a") Nothing (ELiteral () (LString "Hello")))

test_let2 = do
    assertExprParses letExpression "let a = (5)"
        (ELet () LImmutable (PBinding "a") Nothing (ELiteral () (LInteger 5)))

test_let_with_uppercase_is_not_ok = do
    let source = "let PORT = 8000;"
    r <- runParse letExpression source
    case r of
        Right _ -> assertFailure "It shouldn't be legal to assign to an uppercased symbol."
        Left _ -> return ()

test_let_with_type_annotation = do
    assertExprParses letExpression "let a : Number = 5"
        (ELet () LImmutable (PBinding "a") (Just (TypeIdent "Number" [])) (ELiteral () (LInteger 5)))

test_record_types_can_have_trailing_comma = do
    assertParseOk typeIdent "{x:Number,}" (RecordIdent [("x", Nothing, TypeIdent "Number" [])]) id

test_let_with_record_annotation = do
    assertExprParses letExpression "let a : {x:Number, y:Number} = ()"
        (ELet () LImmutable (PBinding "a") (Just (RecordIdent
            [ ("x", Nothing, TypeIdent "Number" [])
            , ("y", Nothing, TypeIdent "Number" [])
            ])) (ELiteral () LUnit))

test_let_with_function_annotation = do
    assertExprParses letExpression "let a : (Number) -> Unit = _unsafe_js(\"console.log\")"
        (ELet () LImmutable (PBinding "a") (Just (FunctionIdent [TypeIdent "Number" []] (TypeIdent "Unit" []))) (EApp () (EIdentifier () "_unsafe_js") [ELiteral () (LString "console.log")]))

test_mutable_let = do
    assertExprParses letExpression "let mutable x = 22"
        (ELet () LMutable (PBinding "x") Nothing (ELiteral () (LInteger 22)))

test_pattern = do
    assertParseOk pattern "Cons(a, Cons(b, Nil))"
        (RPConstructor "Cons" [RPIrrefutable $ PBinding "a", RPConstructor "Cons" [RPIrrefutable $ PBinding "b", RPConstructor "Nil" []]]) id

test_match = do
    assertExprParses matchExpression "match hoot { Nil => hodor ; Cons(a, b) => hoober ; }"
        (EMatch () (EIdentifier () "hoot")
            [ Case (RPConstructor "Nil" []) (EIdentifier () "hodor")
            , Case (RPConstructor "Cons" [RPIrrefutable $ PBinding "a", RPIrrefutable $ PBinding "b"]) (EIdentifier () "hoober")
            ])

test_plus = do
    assertExprParses noSemiExpression "5 + 5"
        (EBinIntrinsic () BIPlus (ELiteral () $ LInteger 5) (ELiteral () $ LInteger 5))

test_times = do
    assertExprParses multiplyExpression "8 * 8"
        (EBinIntrinsic () BIMultiply (ELiteral () $ LInteger 8) (ELiteral () $ LInteger 8))

test_polymorphic_data = do
    assertExprParses dataDeclaration "data Maybe a { Some(a), None, };"
        (DData () "Maybe" "hs.ParseTest" ["a"] [Variant () "Some" [TypeIdent "a" []], Variant () "None" []])

test_empty_fun_decl = do
    assertExprParses funDeclaration "fun f() {}"
        (DFun () "f" [] Nothing (ELiteral () $ LUnit))

test_fun_with_return = do
    assertExprParses funDeclaration "fun f() { return 1 }"
        (DFun () "f" [] Nothing (EReturn () $ ELiteral () $ LInteger $ 1))

test_fun_with_argument_annotations = do
    assertExprParses funDeclaration "fun f(x: Number) { 1 }"
        (DFun () "f" [("x", Just $ TypeIdent "Number" [])] Nothing (ELiteral () $ LInteger 1))

test_fun_that_takes_function = do
    assertExprParses funDeclaration "fun f(x: (Number) -> String) { x(1) }"
        (DFun () "f" [("x", Just $ FunctionIdent [TypeIdent "Number" []] (TypeIdent "String" []))] Nothing (EApp () (EIdentifier () "x") [ELiteral () $ LInteger 1]))

test_fun_with_return_annotation = do
    assertExprParses funDeclaration "fun f() : Number { 5 }"
        (DFun () "f" [] (Just $ TypeIdent "Number" []) (ELiteral () $ LInteger 5))

test_prop_and_functions_chain = do
    assertExprParses noSemiExpression "a()().b.c().d().e.f"
        (ELookup () (ELookup () (EApp () (ELookup () (EApp () (ELookup () (ELookup () (EApp () (EApp () (EIdentifier () "a") []) []) "b") "c") []) "d") []) "e") "f")

test_let_if_indentation = do
    assertExprParses letDeclaration "let x = if\n True\nthen\n 1\nelse\n 2"
        (DLet () LImmutable (PBinding "x") Nothing $ EIfThenElse () (EIdentifier () "True") (ELiteral () $ LInteger 1) (ELiteral () $ LInteger 2))

test_multiline_function_argument_indentation = do
    assertExprParses letDeclaration "let x = foo(fun() {\n}, 1)"
        (DLet () LImmutable (PBinding "x") Nothing $ EApp () (EIdentifier () "foo") [EFun () [] Nothing $ ELiteral () LUnit, ELiteral () $ LInteger 1])

test_parameter_list_indentation = do
    let source = T.unlines
            [ "let _ = foo("
            , "  1,"
            , "  2,"
            , ")"
            ]
    assertExprParses letDeclaration source
        (DLet () LImmutable PWildcard Nothing $ EApp () (EIdentifier () "foo") [ELiteral () $ LInteger 1, ELiteral () $ LInteger 2])

test_record_literal_trailing_comma = do
    let source = T.unlines
            [ "let _ = {"
            , "  a: 1,"
            , "  b: 2,"
            , "}"
            ]
    assertExprParses letDeclaration source
        (DLet () LImmutable PWildcard Nothing $ ERecordLiteral () $ fromList [("a", ELiteral () $ LInteger 1), ("b", ELiteral () $ LInteger 2)])
