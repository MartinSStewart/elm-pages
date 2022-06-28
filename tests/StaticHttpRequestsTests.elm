module StaticHttpRequestsTests exposing (all)

import ApiRoute
import Bytes.Decode
import Bytes.Encode
import Codec
import DataSource exposing (DataSource)
import DataSource.Http
import Dict
import Expect
import Html
import Http
import Json.Decode as JD exposing (Decoder)
import Json.Encode as Encode
import Pages.Internal.NotFoundReason
import Pages.Internal.Platform.Cli exposing (..)
import Pages.Internal.Platform.Effect as Effect exposing (Effect)
import Pages.Internal.Platform.ToJsPayload as ToJsPayload
import Pages.ProgramConfig exposing (ProgramConfig)
import Pages.SiteConfig exposing (SiteConfig)
import Pages.StaticHttp.Request as Request
import Path
import ProgramTest exposing (ProgramTest)
import Regex
import RenderRequest
import RequestsAndPending exposing (ResponseBody(..))
import Server.Response as Response
import SimulatedEffect.Cmd
import SimulatedEffect.Ports
import Task
import Test exposing (Test, describe, test)


all : Test
all =
    describe "Static Http Requests"
        [ test "initial requests are sent out" <|
            \() ->
                startSimple []
                    (DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages" starDecoder)
                    |> simulateHttp
                        (get "https://api.github.com/repos/dillonkearns/elm-pages")
                        (JsonBody
                            (Encode.object [ ( "stargazer_count", Encode.int 86 ) ])
                        )
                    |> expectSuccess []
        , test "StaticHttp request for initial are resolved" <|
            \() ->
                startSimple
                    [ "post-1" ]
                    (DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages" starDecoder)
                    |> simulateHttp
                        (get "https://api.github.com/repos/dillonkearns/elm-pages")
                        (JsonBody
                            (Encode.object [ ( "stargazer_count", Encode.int 86 ) ])
                        )
                    |> expectSuccess []
        , describe "single page renders"
            [ test "single pages that are pre-rendered" <|
                \() ->
                    startSimple [ "post-1" ]
                        (DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages" starDecoder)
                        |> simulateHttp
                            (get "https://api.github.com/repos/dillonkearns/elm-pages")
                            (JsonBody
                                (Encode.object [ ( "stargazer_count", Encode.int 86 ) ])
                            )
                        |> ProgramTest.expectOutgoingPortValues
                            "toJsPort"
                            (Codec.decoder (ToJsPayload.successCodecNew2 "" ""))
                            (\actualPorts ->
                                case actualPorts of
                                    [ ToJsPayload.PageProgress portData ] ->
                                        portData.is404
                                            |> Expect.false "Expected page to be found and rendered"

                                    _ ->
                                        Expect.fail <| "Expected exactly 1 port of type PageProgress. Instead, got \n" ++ Debug.toString actualPorts
                            )
            ]
        , test "the stripped JSON from the same request with different decoders is merged so the decoders succeed" <|
            \() ->
                startSimple
                    [ "post-1" ]
                    (DataSource.map2 Tuple.pair
                        (DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages"
                            (JD.field "stargazer_count" JD.int)
                        )
                        (DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages"
                            (JD.field "language" JD.string)
                        )
                    )
                    |> simulateHttp
                        (get "https://api.github.com/repos/dillonkearns/elm-pages")
                        (JsonBody
                            (Encode.object
                                [ ( "stargazer_count", Encode.int 86 )
                                , ( "language", Encode.string "Elm" )
                                ]
                            )
                        )
                    |> expectSuccess []
        , test "andThen" <|
            \() ->
                startSimple
                    [ "elm-pages" ]
                    (DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages" (JD.succeed ())
                        |> DataSource.andThen
                            (\_ ->
                                DataSource.Http.get "NEXT-REQUEST" (JD.succeed ())
                            )
                    )
                    |> simulateHttp
                        (get "https://api.github.com/repos/dillonkearns/elm-pages")
                        (JsonBody Encode.null)
                    |> simulateHttp
                        (get "NEXT-REQUEST")
                        (JsonBody Encode.null)
                    |> expectSuccess []
        , test "andThen chain avoids repeat requests" <|
            \() ->
                let
                    pokemonDetailRequest : DataSource ()
                    pokemonDetailRequest =
                        DataSource.Http.get
                            "https://pokeapi.co/api/v2/pokemon/"
                            (JD.list
                                (JD.field "url" JD.string
                                    |> JD.map
                                        (\url ->
                                            DataSource.Http.get url
                                                (JD.field "image" JD.string)
                                        )
                                )
                            )
                            |> DataSource.resolve
                            |> DataSource.map (\_ -> ())
                in
                startSimple
                    [ "elm-pages" ]
                    pokemonDetailRequest
                    |> simulateMultipleHttp
                        [ ( get "https://pokeapi.co/api/v2/pokemon/"
                          , jsonBody """[
                            {"url": "url1"},
                            {"url": "url2"},
                            {"url": "url3"},
                            {"url": "url4"},
                            {"url": "url5"},
                            {"url": "url6"},
                            {"url": "url7"},
                            {"url": "url8"},
                            {"url": "url9"},
                            {"url": "url10"}
                            ]"""
                          )
                        , ( get "url1"
                          , jsonBody """{"image": "image1.jpg"}"""
                          )
                        , ( get "url2"
                          , jsonBody """{"image": "image2.jpg"}"""
                          )
                        , ( get "url3"
                          , jsonBody """{"image": "image3.jpg"}"""
                          )
                        , ( get "url4"
                          , jsonBody """{"image": "image4.jpg"}"""
                          )
                        , ( get "url5"
                          , jsonBody """{"image": "image5.jpg"}"""
                          )
                        , ( get "url6"
                          , jsonBody """{"image": "image6.jpg"}"""
                          )
                        , ( get "url7"
                          , jsonBody """{"image": "image7.jpg"}"""
                          )
                        , ( get "url8"
                          , jsonBody """{"image": "image8.jpg"}"""
                          )
                        , ( get "url9"
                          , jsonBody """{"image": "image9.jpg"}"""
                          )
                        , ( get "url10"
                          , jsonBody """{"image": "image10.jpg"}"""
                          )
                        ]
                    |> expectSuccess []

        --, test "port is sent out once all requests are finished" <|
        --    \() ->
        --        start
        --            [ ( [ "elm-pages" ]
        --              , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages") starDecoder
        --              )
        --            , ( [ "elm-pages-starter" ]
        --              , DataSource.Http.get (Secrets.succeed "https://api.github.com/repos/dillonkearns/elm-pages-starter") starDecoder
        --              )
        --            ]
        --            |> ProgramTest.simulateHttpOk
        --                "GET"
        --                "https://api.github.com/repos/dillonkearns/elm-pages"
        --                """{ "stargazer_count": 86 }"""
        --            |> ProgramTest.simulateHttpOk
        --                "GET"
        --                "https://api.github.com/repos/dillonkearns/elm-pages-starter"
        --                """{ "stargazer_count": 22 }"""
        --            |> expectSuccess
        --                [ ( "elm-pages"
        --                  , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
        --                      , """{"stargazer_count":86}"""
        --                      )
        --                    ]
        --                  )
        --                , ( "elm-pages-starter"
        --                  , [ ( get "https://api.github.com/repos/dillonkearns/elm-pages-starter"
        --                      , """{"stargazer_count":22}"""
        --                      )
        --                    ]
        --                  )
        --                ]
        , test "reduced JSON is sent out" <|
            \() ->
                startSimple []
                    (DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages" (JD.field "stargazer_count" JD.int))
                    |> simulateHttp
                        (get "https://api.github.com/repos/dillonkearns/elm-pages")
                        (jsonBody """{ "stargazer_count": 86, "unused_field": 123 }""")
                    |> expectSuccess []
        , test "you can use elm/json decoders with StaticHttp.unoptimizedRequest" <|
            \() ->
                startSimple []
                    (DataSource.Http.request
                        { url = "https://api.github.com/repos/dillonkearns/elm-pages"
                        , method = "GET"
                        , headers = []
                        , body = DataSource.Http.emptyBody
                        }
                        (DataSource.Http.expectJson
                            (JD.field "stargazer_count" JD.int)
                        )
                    )
                    |> simulateHttp
                        (get "https://api.github.com/repos/dillonkearns/elm-pages")
                        (jsonBody """{ "stargazer_count": 86, "unused_field": 123 }""")
                    |> expectSuccess []
        , test "plain string" <|
            \() ->
                startSimple []
                    (DataSource.Http.request
                        { url = "https://example.com/file.txt"
                        , method = "GET"
                        , headers = []
                        , body = DataSource.Http.emptyBody
                        }
                        DataSource.Http.expectString
                    )
                    |> simulateHttp
                        { method = "GET"
                        , url = "https://example.com/file.txt"
                        , headers =
                            []
                        , body = DataSource.Http.emptyBody
                        }
                        (StringBody "This is a raw text file.")
                    |> expectSuccess []
        , test "Err in String to Result function turns into decode error" <|
            \() ->
                startSimple []
                    (DataSource.Http.request
                        { url = "https://example.com/file.txt"
                        , method = "GET"
                        , headers = []
                        , body = DataSource.Http.emptyBody
                        }
                        DataSource.Http.expectString
                        |> DataSource.map
                            (\string ->
                                if String.toUpper string == string then
                                    Ok string

                                else
                                    Err "String was not uppercased"
                            )
                        |> DataSource.andThen DataSource.fromResult
                    )
                    |> simulateHttp
                        (get "https://example.com/file.txt")
                        (StringBody "This is a raw text file.")
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder (ToJsPayload.successCodecNew2 "" ""))
                        (expectErrorsPort
                            """-- CALLED STATIC HTTP FAIL ----------------------------------------------------- elm-pages



I ran into a call to `DataSource.fail` with message: String was not uppercased"""
                        )
        , test "POST method works" <|
            \() ->
                startSimple []
                    (DataSource.Http.request
                        { method = "POST"
                        , url = "https://api.github.com/repos/dillonkearns/elm-pages"
                        , headers = []
                        , body = DataSource.Http.emptyBody
                        }
                        (DataSource.Http.expectJson
                            (JD.field "stargazer_count" JD.int)
                        )
                    )
                    |> simulateHttp
                        (post "https://api.github.com/repos/dillonkearns/elm-pages")
                        (jsonBody """{ "stargazer_count": 86, "unused_field": 123 }""")
                    |> expectSuccess []
        , test "json is reduced from andThen chains" <|
            \() ->
                startSimple []
                    (DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages" (JD.field "stargazer_count" JD.int)
                        |> DataSource.andThen
                            (\_ ->
                                DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages-starter" (JD.field "stargazer_count" JD.int)
                            )
                    )
                    |> simulateHttp
                        (get "https://api.github.com/repos/dillonkearns/elm-pages")
                        (jsonBody """{ "stargazer_count": 100, "unused_field": 123 }""")
                    |> simulateHttp
                        (get "https://api.github.com/repos/dillonkearns/elm-pages-starter")
                        (jsonBody """{ "stargazer_count": 50, "unused_field": 456 }""")
                    |> expectSuccess []
        , test "reduced json is preserved by StaticHttp.map2" <|
            \() ->
                startSimple []
                    (DataSource.map2 (\_ _ -> ())
                        (DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages" (JD.field "stargazer_count" JD.int))
                        (DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages-starter" (JD.field "stargazer_count" JD.int))
                    )
                    |> simulateMultipleHttp
                        [ ( get "https://api.github.com/repos/dillonkearns/elm-pages"
                          , jsonBody """{ "stargazer_count": 100, "unused_field": 123 }"""
                          )
                        , ( get "https://api.github.com/repos/dillonkearns/elm-pages-starter"
                          , jsonBody """{ "stargazer_count": 50, "unused_field": 456 }"""
                          )
                        ]
                    |> expectSuccess []
        , test "the port sends out even if there are no http requests" <|
            \() ->
                start
                    [ ( []
                      , DataSource.succeed ()
                      )
                    ]
                    |> expectSuccess []
        , test "the port sends out when there are duplicate http requests for the same page" <|
            \() ->
                startSimple []
                    (DataSource.map2 (\_ _ -> ())
                        (DataSource.Http.get "http://example.com" (JD.succeed ()))
                        (DataSource.Http.get "http://example.com" (JD.succeed ()))
                    )
                    |> simulateHttp
                        (get "http://example.com")
                        (jsonBody """null""")
                    |> expectSuccess []
        , test "an error is sent out for decoder failures" <|
            \() ->
                startSimple [ "elm-pages" ]
                    (DataSource.Http.get "https://api.github.com/repos/dillonkearns/elm-pages" (JD.fail "The user should get this message from the CLI."))
                    |> simulateHttp
                        (get "https://api.github.com/repos/dillonkearns/elm-pages")
                        (jsonBody """{ "stargazer_count": 86 }""")
                    |> ProgramTest.expectOutgoingPortValues
                        "toJsPort"
                        (Codec.decoder (ToJsPayload.successCodecNew2 "" ""))
                        (expectErrorsPort
                            """-- STATIC HTTP DECODING ERROR ----------------------------------------------------- elm-pages

Problem with the given value:

{
   "stargazer_count": 86
}

The user should get this message from the CLI."""
                        )
        ]


type Route
    = Route String


start : List ( List String, DataSource a ) -> ProgramTest (Model Route) Msg Effect
start pages =
    startWithHttpCache [] pages


startWithHttpCache :
    List ( Request.Request, String )
    -> List ( List String, DataSource a )
    -> ProgramTest (Model Route) Msg Effect
startWithHttpCache =
    startLowLevel []


startLowLevel :
    List (ApiRoute.ApiRoute ApiRoute.Response)
    -> List ( Request.Request, String )
    -> List ( List String, DataSource a )
    -> ProgramTest (Model Route) Msg Effect
startLowLevel apiRoutes staticHttpCache pages =
    let
        pageToLoad : List String
        pageToLoad =
            case pages |> List.head |> Maybe.map Tuple.first of
                Just justPageToLoad ->
                    justPageToLoad

                Nothing ->
                    Debug.todo "Error - no pages"

        encodedFlags : Encode.Value
        encodedFlags =
            --{"secrets":
            --        {"API_KEY": "ABCD1234","BEARER": "XYZ789"}, "mode": "prod", "staticHttpCache": {}
            --        }
            Encode.object
                [ ( "secrets"
                  , [ ( "API_KEY", "ABCD1234" )
                    , ( "BEARER", "XYZ789" )
                    ]
                        |> Dict.fromList
                        |> Encode.dict identity Encode.string
                  )
                , ( "mode", Encode.string "prod" )
                , ( "staticHttpCache", encodedStaticHttpCache )
                ]

        encodedStaticHttpCache : Encode.Value
        encodedStaticHttpCache =
            staticHttpCache
                |> List.map
                    (\( request, httpResponseString ) ->
                        ( Request.hash request, Encode.string httpResponseString )
                    )
                |> Encode.object
    in
    {-
       (Model -> model)
       -> ContentCache.ContentCache metadata view
       -> Result (List BuildError) (List ( PagePath, metadata ))
       -> Config pathKey userMsg userModel metadata view
       -> Decode.Value
       -> ( model, Effect pathKey )
    -}
    ProgramTest.createDocument
        { init =
            init
                site
                (RenderRequest.SinglePage
                    RenderRequest.OnlyJson
                    (RenderRequest.Page
                        { path = Path.fromString (pageToLoad |> String.join "/")
                        , frontmatter = Route (pageToLoad |> String.join "/")
                        }
                    )
                    (Encode.object [])
                )
                (config apiRoutes pages)
        , update = update site (config apiRoutes pages)
        , view = \_ -> { title = "", body = [] }
        }
        |> ProgramTest.withSimulatedEffects simulateEffects
        |> ProgramTest.start (flags (Encode.encode 0 encodedFlags))


site : SiteConfig
site =
    { canonicalUrl = "canonical-site-url"
    , head = DataSource.succeed []
    }


startSimple : List String -> DataSource a -> ProgramTest (Model Route) Msg Effect
startSimple route dataSources =
    startWithRoutes route [ route ] [] [ ( route, dataSources ) ]


config : List (ApiRoute.ApiRoute ApiRoute.Response) -> List ( List String, DataSource a ) -> ProgramConfig Msg () Route () () () Effect mappedMsg ()
config apiRoutes pages =
    { toJsPort = toJsPort
    , fromJsPort = fromJsPort
    , init = \_ _ _ _ _ _ -> ( (), Effect.NoEffect )
    , getStaticRoutes =
        --StaticHttp.get (Secrets.succeed "https://my-cms.com/posts")
        --    (Decode.field "posts" (Decode.list (Decode.string |> Decode.map Route)))
        pages
            |> List.map Tuple.first
            |> List.map (String.join "/")
            |> List.map Route
            |> DataSource.succeed
    , handleRoute = \_ -> DataSource.succeed Nothing
    , urlToRoute = .path >> Route
    , update = \_ _ _ _ _ _ _ _ -> ( (), Effect.NoEffect )
    , basePath = []
    , onActionData = \() -> Nothing
    , data =
        \(Route pageRoute) ->
            let
                thing : Maybe (DataSource a)
                thing =
                    pages
                        |> Dict.fromList
                        |> Dict.get
                            (pageRoute
                                |> String.split "/"
                                |> List.filter (\pathPart -> pathPart /= "")
                            )
            in
            case thing of
                Just request ->
                    request |> DataSource.map (\_ -> Response.render ())

                Nothing ->
                    Debug.todo <| "Couldn't find page: " ++ pageRoute ++ "\npages: " ++ Debug.toString pages
    , site = Just site
    , view =
        \_ _ _ page _ _ _ _ ->
            let
                thing : Maybe (DataSource a)
                thing =
                    pages
                        |> Dict.fromList
                        |> Dict.get
                            (page.path |> Path.toSegments)
            in
            case thing of
                Just _ ->
                    { view = \_ -> { title = "Title", body = Html.text "" }, head = [] }

                Nothing ->
                    Debug.todo <| "Couldn't find page: " ++ Debug.toString page ++ "\npages: " ++ Debug.toString pages
    , subscriptions = \_ _ _ -> Sub.none
    , routeToPath = \(Route route) -> route |> String.split "/"
    , sharedData = DataSource.succeed ()
    , onPageChange = \_ -> Continue
    , apiRoutes = \_ -> apiRoutes
    , pathPatterns = []
    , byteDecodePageData = \_ -> Bytes.Decode.fail
    , sendPageData = \_ -> Cmd.none
    , encodeResponse = \_ -> Bytes.Encode.signedInt8 0
    , hotReloadData = Sub.none
    , decodeResponse = Bytes.Decode.fail
    , byteEncodePageData = \_ -> Bytes.Encode.signedInt8 0
    , gotBatchSub = Sub.none
    , globalHeadTags = Nothing
    , perform = \_ _ -> Cmd.none
    , cmdToEffect = \_ -> Effect.NoEffect
    , errorStatusCode = \_ -> 404
    , notFoundPage = ()
    , notFoundRoute = Route "not-found"
    , internalError = \_ -> ()
    , errorPageToData = \_ -> ()
    , action = \_ -> DataSource.fail "No action."
    , encodeAction = \_ -> Bytes.Encode.signedInt8 0
    }


startWithRoutes :
    List String
    -> List (List String)
    -> List ( Request.Request, String )
    -> List ( List String, DataSource a )
    -> ProgramTest (Model Route) Msg Effect
startWithRoutes pageToLoad staticRoutes staticHttpCache pages =
    let
        encodedFlags : Encode.Value
        encodedFlags =
            --{"secrets":
            --        {"API_KEY": "ABCD1234","BEARER": "XYZ789"}, "mode": "prod", "staticHttpCache": {}
            --        }
            Encode.object
                [ ( "secrets"
                  , [ ( "API_KEY", "ABCD1234" )
                    , ( "BEARER", "XYZ789" )
                    ]
                        |> Dict.fromList
                        |> Encode.dict identity Encode.string
                  )
                , ( "staticHttpCache", encodedStaticHttpCache )
                , ( "mode", Encode.string "dev-server" )
                ]

        encodedStaticHttpCache : Encode.Value
        encodedStaticHttpCache =
            staticHttpCache
                |> List.map
                    (\( request, httpResponseString ) ->
                        ( Request.hash request, Encode.string httpResponseString )
                    )
                |> Encode.object
    in
    {-
       (Model -> model)
       -> ContentCache.ContentCache metadata view
       -> Result (List BuildError) (List ( PagePath, metadata ))
       -> Config pathKey userMsg userModel metadata view
       -> Decode.Value
       -> ( model, Effect pathKey )
    -}
    ProgramTest.createDocument
        { init =
            init
                site
                (RenderRequest.SinglePage
                    RenderRequest.OnlyJson
                    (RenderRequest.Page
                        { path = Path.fromString (pageToLoad |> String.join "/")
                        , frontmatter = Route (pageToLoad |> String.join "/")
                        }
                    )
                    (Encode.object [])
                )
                (config [] pages)
        , update = update site (config [] pages)
        , view = \_ -> { title = "", body = [] }
        }
        |> ProgramTest.withSimulatedEffects simulateEffects
        |> ProgramTest.withSimulatedSubscriptions simulateSubscriptions
        |> ProgramTest.start (flags (Encode.encode 0 encodedFlags))


flags : String -> JD.Value
flags jsonString =
    case JD.decodeString JD.value jsonString of
        Ok value ->
            value

        Err _ ->
            Debug.todo "Invalid JSON value."


sendToJsPort : ToJsPayload.ToJsSuccessPayloadNewCombined -> ProgramTest.SimulatedEffect msg
sendToJsPort value =
    SimulatedEffect.Ports.send "toJsPort" (value |> Codec.encoder (ToJsPayload.successCodecNew2 "" ""))


simulateEffects : Effect -> ProgramTest.SimulatedEffect Msg
simulateEffects effect =
    case effect of
        Effect.NoEffect ->
            SimulatedEffect.Cmd.none

        --            toJsPort value |> Cmd.map never
        Effect.Batch list ->
            list
                |> List.map simulateEffects
                |> SimulatedEffect.Cmd.batch

        Effect.FetchHttp unmasked ->
            if unmasked.url |> String.startsWith "port://" then
                let
                    portName : String
                    portName =
                        String.dropLeft 7 unmasked.url
                in
                ToJsPayload.Port portName
                    |> sendToJsPort
                    |> SimulatedEffect.Cmd.map never

            else
                ToJsPayload.DoHttp
                    (unmasked
                     --|> withInternalHeader
                    )
                    |> sendToJsPort
                    |> SimulatedEffect.Cmd.map never

        Effect.SendSinglePage info ->
            SimulatedEffect.Cmd.batch
                [ info
                    |> Codec.encoder (ToJsPayload.successCodecNew2 "" "")
                    |> SimulatedEffect.Ports.send "toJsPort"
                , SimulatedEffect.Cmd.none
                ]

        Effect.Continue ->
            SimulatedEffect.Cmd.none

        Effect.SendSinglePageNew _ toJsSuccessPayloadNewCombined ->
            SimulatedEffect.Cmd.batch
                [ toJsSuccessPayloadNewCombined
                    |> Codec.encoder (ToJsPayload.successCodecNew2 "" "")
                    |> SimulatedEffect.Ports.send "toJsPort"
                , SimulatedEffect.Cmd.none
                ]


expectErrorsPort : String -> List ToJsPayload.ToJsSuccessPayloadNewCombined -> Expect.Expectation
expectErrorsPort expectedPlainString actualPorts =
    case actualPorts |> List.reverse |> List.head of
        Just (ToJsPayload.Errors actualRichTerminalString) ->
            actualRichTerminalString
                |> List.map .title
                |> String.join "\n"
                |> normalizeErrorExpectEqual expectedPlainString

        Nothing ->
            Expect.fail "Expected single error port. Didn't receive any ports."

        _ ->
            Expect.fail <| "Expected single error port. Got\n" ++ String.join "\n\n" (List.map Debug.toString actualPorts)


normalizeErrorExpectEqual : String -> String -> Expect.Expectation
normalizeErrorExpectEqual expectedPlainString actualRichTerminalString =
    actualRichTerminalString
        |> Regex.replace
            -- strip out all possible ANSI sequences
            (Regex.fromString "(\\x9B|\\x1B\\[)[0-?]*[ -/]*[@-~]"
                |> Maybe.withDefault Regex.never
            )
            (\_ -> "")
        |> String.replace "\u{001B}" ""
        |> normalizeNewlines
        |> Expect.equal
            (expectedPlainString |> normalizeNewlines)


normalizeNewlines : String -> String
normalizeNewlines string =
    string
        |> Regex.replace
            (Regex.fromString "(\n)+" |> Maybe.withDefault Regex.never)
            (\_ -> "")
        |> Regex.replace
            (Regex.fromString "( )+" |> Maybe.withDefault Regex.never)
            (\_ -> " ")
        |> String.replace "\u{000D}" ""
        |> Regex.replace
            (Regex.fromString "\\s" |> Maybe.withDefault Regex.never)
            (\_ -> "")


toJsPort : a -> Cmd msg
toJsPort _ =
    Cmd.none


fromJsPort : Sub msg
fromJsPort =
    Sub.none


starDecoder : Decoder Int
starDecoder =
    JD.field "stargazer_count" JD.int


expectSuccess : List ( Request.Request, String ) -> ProgramTest model msg effect -> Expect.Expectation
expectSuccess expectedRequests previous =
    expectSuccessNew expectedRequests [] previous


expectSuccessNew : List ( Request.Request, String ) -> List (ToJsPayload.ToJsSuccessPayloadNew -> Expect.Expectation) -> ProgramTest model msg effect -> Expect.Expectation
expectSuccessNew expectedRequest expectations previous =
    previous
        |> ProgramTest.expectOutgoingPortValues
            "toJsPort"
            (Codec.decoder (ToJsPayload.successCodecNew2 "" ""))
            (\value ->
                case value of
                    (ToJsPayload.PageProgress portPayload) :: _ ->
                        let
                            singleExpectation : ToJsPayload.ToJsSuccessPayloadNew -> Expect.Expectation
                            singleExpectation =
                                \subject ->
                                    subject.contentJson
                                        |> Expect.equal
                                            (expectedRequest
                                                |> List.map
                                                    (\( request, response ) ->
                                                        ( Request.hash request, response )
                                                    )
                                                |> Dict.fromList
                                            )
                        in
                        portPayload
                            |> Expect.all
                                (singleExpectation
                                    :: expectations
                                )

                    [ errorPort ] ->
                        Expect.fail <| "Expected success port. Got:\n" ++ Debug.toString errorPort

                    _ ->
                        Expect.fail ("Expected ports to be called once, but instead there were " ++ String.fromInt (List.length value) ++ " calls.")
            )


simulateSubscriptions : a -> ProgramTest.SimulatedSub Msg
simulateSubscriptions _ =
    -- TODO handle build errors or not needed?
    SimulatedEffect.Ports.subscribe "gotBatchSub"
        (RequestsAndPending.batchDecoder |> JD.map GotDataBatch)
        identity


get : String -> Request.Request
get url =
    { method = "GET"
    , url = url
    , headers = []
    , body = DataSource.Http.emptyBody
    }


post : String -> Request.Request
post url =
    { method = "POST"
    , url = url
    , headers = []
    , body = DataSource.Http.emptyBody
    }


simulateHttp : Request.Request -> ResponseBody -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateHttp request response program =
    program
        |> ProgramTest.ensureOutgoingPortValues
            "toJsPort"
            (Codec.decoder (ToJsPayload.successCodecNew2 "" ""))
            (\actualPorts ->
                case actualPorts of
                    [ ToJsPayload.DoHttp _ ] ->
                        Expect.pass

                    _ ->
                        Expect.fail <|
                            "Expected an HTTP request, got:\n"
                                ++ Debug.toString actualPorts
            )
        |> ProgramTest.simulateIncomingPort "gotBatchSub"
            (Encode.list (\req -> encodeBatchEntry req response)
                [ request ]
            )


simulateMultipleHttp : List ( Request.Request, ResponseBody ) -> ProgramTest model msg effect -> ProgramTest model msg effect
simulateMultipleHttp requests program =
    program
        |> ProgramTest.ensureOutgoingPortValues
            "toJsPort"
            (Codec.decoder (ToJsPayload.successCodecNew2 "" ""))
            (\actualPorts ->
                case actualPorts of
                    (ToJsPayload.DoHttp _) :: _ ->
                        -- TODO check count of HTTP requests, and check the URLs
                        Expect.pass

                    _ ->
                        Expect.fail <|
                            "Expected an HTTP request, got:\n"
                                ++ Debug.toString actualPorts
            )
        |> ProgramTest.simulateIncomingPort "gotBatchSub"
            (requests
                |> Encode.list
                    (\( req, response ) ->
                        encodeBatchEntry req response
                    )
            )


jsonBody : String -> ResponseBody
jsonBody jsonString =
    JsonBody
        (jsonString
            |> JD.decodeString JD.value
            |> Result.withDefault Encode.null
        )


encodeBatchEntry : Request.Request -> ResponseBody -> Encode.Value
encodeBatchEntry req response =
    Encode.object
        [ ( "request"
          , Codec.encodeToValue Request.codec
                (withInternalHeader response req)
          )
        , ( "response"
          , RequestsAndPending.bodyEncoder response
          )
        ]


withInternalHeader : ResponseBody -> { a | headers : List ( String, String ) } -> { a | headers : List ( String, String ) }
withInternalHeader res req =
    { req
        | headers =
            ( "elm-pages-internal"
            , case res of
                JsonBody _ ->
                    "ExpectJson"

                BytesBody _ ->
                    "ExpectBytes"

                StringBody _ ->
                    "ExpectString"

                WhateverBody ->
                    "ExpectWhatever"
            )
                :: req.headers
    }
