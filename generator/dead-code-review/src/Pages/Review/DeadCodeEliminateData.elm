module Pages.Review.DeadCodeEliminateData exposing (rule)

import Dict exposing (Dict)
import Elm.Syntax.Declaration as Declaration exposing (Declaration)
import Elm.Syntax.Exposing exposing (Exposing)
import Elm.Syntax.Expression as Expression exposing (Expression)
import Elm.Syntax.Import exposing (Import)
import Elm.Syntax.ModuleName exposing (ModuleName)
import Elm.Syntax.Node as Node exposing (Node)
import Review.Fix
import Review.ModuleNameLookupTable as ModuleNameLookupTable exposing (ModuleNameLookupTable)
import Review.Rule as Rule exposing (Error, Rule)


type alias Context =
    { lookupTable : ModuleNameLookupTable
    , importContext : Dict (List String) ImportContext
    }


type ImportReference
    = QualifiedReference
    | UnqualifiedReference (List String)


type alias ImportContext =
    { moduleName : ModuleName
    , moduleAlias : Maybe ModuleName
    , exposedFunctions : Exposed

    --Maybe Exposing
    }


type Exposed
    = AllExposed
    | SomeExposed (List String)


toImportContext : Import -> ( List String, ImportContext )
toImportContext import_ =
    ( import_.moduleName |> Node.value
    , { moduleName = import_.moduleName |> Node.value
      , moduleAlias = import_.moduleAlias |> Maybe.map Node.value
      , exposedFunctions =
            import_.exposingList
                |> Maybe.map Node.value
                |> Maybe.map
                    (\exposingList ->
                        case exposingList of
                            Elm.Syntax.Exposing.All _ ->
                                AllExposed

                            Elm.Syntax.Exposing.Explicit nodes ->
                                AllExposed
                    )
                |> Maybe.withDefault (SomeExposed [])
      }
    )


rule : Rule
rule =
    Rule.newModuleRuleSchemaUsingContextCreator "Pages.Review.DeadCodeEliminateData" initialContext
        |> Rule.withExpressionEnterVisitor expressionVisitor
        |> Rule.withDeclarationEnterVisitor declarationVisitor
        |> Rule.withImportVisitor importVisitor
        |> Rule.fromModuleRuleSchema


initialContext : Rule.ContextCreator () Context
initialContext =
    Rule.initContextCreator
        (\lookupTable () ->
            { lookupTable = lookupTable
            , importContext = Dict.empty
            }
        )
        |> Rule.withModuleNameLookupTable


importVisitor : Node Import -> Context -> ( List (Rule.Error {}), Context )
importVisitor node context =
    let
        ( key, value ) =
            Node.value node
                |> toImportContext
    in
    ( []
    , { context
        | importContext =
            context.importContext |> Dict.insert key value
      }
    )


declarationVisitor : Node Declaration -> Context -> ( List (Error {}), Context )
declarationVisitor node context =
    case Node.value node of
        Declaration.FunctionDeclaration { declaration } ->
            case Node.value declaration of
                { name, expression } ->
                    case ( Node.value name, Node.value expression ) of
                        ( "template", Expression.RecordExpr setters ) ->
                            let
                                dataFieldValue : Maybe (Node ( Node String, Node Expression ))
                                dataFieldValue =
                                    setters
                                        |> List.filterMap
                                            (\recordSetter ->
                                                case Node.value recordSetter of
                                                    ( keyNode, valueNode ) ->
                                                        if Node.value keyNode == "data" || Node.value keyNode == "action" then
                                                            if isAlreadyApplied context.lookupTable (Node.value valueNode) then
                                                                Nothing

                                                            else
                                                                recordSetter |> Just

                                                        else
                                                            Nothing
                                            )
                                        |> List.head
                            in
                            dataFieldValue
                                |> Maybe.map
                                    (\dataValue ->
                                        ( [ Rule.errorWithFix
                                                { message = "Codemod"
                                                , details = [ "" ]
                                                }
                                                (Node.range dataValue)
                                                -- TODO need to check the right way to refer to `DataSource.fail` based on imports
                                                -- TODO need to replace `action` as well
                                                [ Review.Fix.replaceRangeBy (Node.range dataValue) "data = DataSource.fail \"\"\n    "
                                                ]
                                          ]
                                        , context
                                        )
                                    )
                                |> Maybe.withDefault
                                    ( [], context )

                        _ ->
                            ( [], context )

        _ ->
            ( [], context )


expressionVisitor : Node Expression -> Context -> ( List (Error {}), Context )
expressionVisitor node context =
    case Node.value node of
        Expression.Application applicationExpressions ->
            case applicationExpressions |> List.map (\applicationNode -> ( ModuleNameLookupTable.moduleNameFor context.lookupTable applicationNode, Node.value applicationNode )) of
                [ ( Just [ "RouteBuilder" ], Expression.FunctionOrValue _ pageBuilderName ), ( _, Expression.RecordExpr fields ) ] ->
                    let
                        dataFieldValue : List ( String, Node ( Node String, Node Expression ) )
                        dataFieldValue =
                            fields
                                |> List.filterMap
                                    (\recordSetter ->
                                        case Node.value recordSetter of
                                            ( keyNode, valueNode ) ->
                                                if Node.value keyNode == "data" || Node.value keyNode == "action" then
                                                    if isAlreadyApplied context.lookupTable (Node.value valueNode) then
                                                        Nothing

                                                    else
                                                        ( Node.value keyNode, recordSetter ) |> Just

                                                else
                                                    Nothing
                                    )
                    in
                    ( dataFieldValue
                        |> List.concatMap
                            (\( key, dataValue ) ->
                                [ Rule.errorWithFix
                                    { message = "Codemod"
                                    , details = [ "" ]
                                    }
                                    (Node.range dataValue)
                                    [ Review.Fix.replaceRangeBy (Node.range dataValue)
                                        (key
                                            ++ " = "
                                            ++ (case pageBuilderName of
                                                    "preRender" ->
                                                        "\\_ -> DataSource.fail \"\""

                                                    "preRenderWithFallback" ->
                                                        "\\_ -> DataSource.fail \"\""

                                                    "serverRender" ->
                                                        "\\_ -> "
                                                            ++ referenceFunction context.importContext ( [ "Server", "Request" ], "oneOf" )
                                                            ++ " []\n        "

                                                    "single" ->
                                                        "DataSource.fail \"\"\n       "

                                                    _ ->
                                                        "data"
                                               )
                                        )
                                    ]
                                ]
                            )
                    , context
                    )

                _ ->
                    ( [], context )

        _ ->
            ( [], context )


referenceFunction : Dict (List String) ImportContext -> ( List String, String ) -> String
referenceFunction dict ( rawModuleName, rawFunctionName ) =
    let
        ( moduleName, functionName ) =
            case dict |> Dict.get rawModuleName of
                Just import_ ->
                    ( import_.moduleAlias |> Maybe.withDefault rawModuleName
                    , rawFunctionName
                    )

                Nothing ->
                    ( rawModuleName, rawFunctionName )
    in
    moduleName ++ [ functionName ] |> String.join "."


isAlreadyApplied : ModuleNameLookupTable -> Expression -> Bool
isAlreadyApplied lookupTable expression =
    case expression of
        Expression.LambdaExpression info ->
            case Node.value info.expression of
                Expression.Application applicationNodes ->
                    case applicationNodes |> List.map Node.value of
                        (Expression.FunctionOrValue _ "fail") :: _ ->
                            let
                                resolvedModuleName : ModuleName
                                resolvedModuleName =
                                    applicationNodes
                                        |> List.head
                                        |> Maybe.andThen
                                            (\functionNode ->
                                                ModuleNameLookupTable.moduleNameFor lookupTable functionNode
                                            )
                                        |> Maybe.withDefault []
                            in
                            resolvedModuleName == [ "DataSource" ]

                        (Expression.FunctionOrValue _ "oneOf") :: (Expression.ListExpr []) :: _ ->
                            let
                                resolvedModuleName : ModuleName
                                resolvedModuleName =
                                    applicationNodes
                                        |> List.head
                                        |> Maybe.andThen
                                            (\functionNode ->
                                                ModuleNameLookupTable.moduleNameFor lookupTable functionNode
                                            )
                                        |> Maybe.withDefault []
                            in
                            resolvedModuleName == [ "Server", "Request" ]

                        _ ->
                            False

                _ ->
                    False

        Expression.Application applicationNodes ->
            case applicationNodes |> List.map Node.value of
                (Expression.FunctionOrValue _ "fail") :: _ ->
                    let
                        resolvedModuleName : ModuleName
                        resolvedModuleName =
                            applicationNodes
                                |> List.head
                                |> Maybe.andThen
                                    (\functionNode ->
                                        ModuleNameLookupTable.moduleNameFor lookupTable functionNode
                                    )
                                |> Maybe.withDefault []
                    in
                    resolvedModuleName == [ "DataSource" ]

                _ ->
                    False

        _ ->
            False
