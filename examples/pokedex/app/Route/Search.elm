module Route.Search exposing (ActionData, Data, Model, Msg, route)

import DataSource exposing (DataSource)
import Effect exposing (Effect)
import ErrorPage exposing (ErrorPage)
import Form
import Form.Field as Field
import Form.FieldView
import Form.Validation as Validation exposing (Validation)
import Head
import Head.Seo as Seo
import Html exposing (Html)
import Html.Attributes as Attr
import Pages.Msg
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path exposing (Path)
import RouteBuilder exposing (StatefulRoute, StatelessRoute, StaticPayload)
import Server.Request as Request
import Server.Response as Response exposing (Response)
import Shared
import View exposing (View)


type alias Model =
    {}


type Msg
    = NoOp


type alias RouteParams =
    {}


route : StatefulRoute RouteParams Data ActionData Model Msg
route =
    RouteBuilder.serverRender
        { head = head
        , data = data
        , action = action
        }
        |> RouteBuilder.buildWithLocalState
            { view = view
            , update = update
            , subscriptions = subscriptions
            , init = init
            }


init :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> ( Model, Effect Msg )
init maybePageUrl sharedModel static =
    ( {}, Effect.none )


update :
    PageUrl
    -> Shared.Model
    -> StaticPayload Data ActionData RouteParams
    -> Msg
    -> Model
    -> ( Model, Effect Msg )
update pageUrl sharedModel static msg model =
    case msg of
        NoOp ->
            ( model, Effect.none )


subscriptions : Maybe PageUrl -> RouteParams -> Path -> Shared.Model -> Model -> Sub Msg
subscriptions maybePageUrl routeParams path sharedModel model =
    Sub.none


type alias SearchResults =
    { query : String
    , results : List String
    }


type alias Data =
    { results : Maybe SearchResults
    }


type alias ActionData =
    {}


data : RouteParams -> Request.Parser (DataSource (Response Data ErrorPage))
data routeParams =
    Request.oneOf
        [ Request.formDataWithoutServerValidation2 [ form ]
            |> Request.map
                (\formResult ->
                    DataSource.succeed
                        (Response.render
                            { results =
                                formResult
                                    |> Result.map
                                        (\query ->
                                            Just
                                                { query = query
                                                , results = [ "Hello" ]
                                                }
                                        )
                                    |> Result.withDefault Nothing
                            }
                        )
                )
        , Request.succeed (DataSource.succeed (Response.render { results = Nothing }))
        ]


form : Form.HtmlForm String String () Msg
form =
    Form.init
        (\query ->
            { combine =
                Validation.succeed identity
                    |> Validation.andMap query
            , view =
                \info ->
                    [ query |> fieldView info "Query"
                    , Html.button [] [ Html.text "Search" ]
                    ]
            }
        )
        |> Form.field "q" (Field.text |> Field.required "Required")


fieldView :
    Form.Context String data
    -> String
    -> Validation String parsed Form.FieldView.Input
    -> Html msg
fieldView formState label field =
    Html.div []
        [ Html.label []
            [ Html.text (label ++ " ")
            , field |> Form.FieldView.input2 []
            ]
        , errorsForField formState field
        ]


errorsForField : Form.Context String data -> Validation String parsed kind -> Html msg
errorsForField formState field =
    (if True then
        formState.errors
            |> Form.errorsForField field
            |> List.map (\error -> Html.li [] [ Html.text error ])

     else
        []
    )
        |> Html.ul [ Attr.style "color" "red" ]


action : RouteParams -> Request.Parser (DataSource (Response ActionData ErrorPage))
action routeParams =
    Request.skip "No action."


head :
    StaticPayload Data ActionData RouteParams
    -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "elm-pages"
        , image =
            { url = Pages.Url.external "TODO"
            , alt = "elm-pages logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = "TODO"
        , locale = Nothing
        , title = "TODO title" -- metadata.title -- TODO
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> Model
    -> StaticPayload Data ActionData RouteParams
    -> View (Pages.Msg.Msg Msg)
view maybeUrl sharedModel model static =
    { title = "Search"
    , body =
        [ Html.h2 [] [ Html.text "Search" ]
        , form
            |> Form.toDynamicTransition "test1"
            |> Form.withGetMethod
            |> Form.renderHtml []
                -- TODO pass in server data
                Nothing
                static
                ()
        , static.data.results
            |> Maybe.map resultsView
            |> Maybe.withDefault (Html.div [] [])
        ]
    }


resultsView : SearchResults -> Html msg
resultsView results =
    Html.div []
        [ Html.h2 [] [ Html.text <| "Results matching " ++ results.query ]
        ]
